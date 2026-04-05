import Foundation

extension ConfigLinterService {

    // MARK: - CLAUDE.md Discovery

    func discoverClaudeMdFiles(projectRoot: String?, globalDir: URL) -> [URL] {
        let memFile = workspace.capabilities.memoryFileName ?? "CLAUDE.md"
        var files: [URL] = []

        // Global memory file
        let globalClaudeMd = globalDir.appendingPathComponent(memFile)
        if fm.fileExists(atPath: globalClaudeMd.path) {
            files.append(globalClaudeMd)
        }

        guard let root = projectRoot else { return files }

        let rootURL = URL(fileURLWithPath: root)

        // Project root memory file
        let rootClaudeMd = rootURL.appendingPathComponent(memFile)
        if fm.fileExists(atPath: rootClaudeMd.path) {
            files.append(rootClaudeMd)
        }

        // harness dir memory file (e.g. .claude/CLAUDE.md)
        let dotClaudeMd = claudeDir.appendingPathComponent(memFile)
        if fm.fileExists(atPath: dotClaudeMd.path) {
            files.append(dotClaudeMd)
        }

        // Recursively find subdirectory memory files (depth limit 3, skip common dirs)
        files.append(contentsOf: findClaudeMdRecursive(in: rootURL, currentDepth: 0, maxDepth: 3, exclude: [rootClaudeMd.path, dotClaudeMd.path]))

        return files
    }

    func findClaudeMdRecursive(in directory: URL, currentDepth: Int, maxDepth: Int, exclude: [String]) -> [URL] {
        let memFile = workspace.capabilities.memoryFileName ?? "CLAUDE.md"
        guard currentDepth < maxDepth else { return [] }
        var found: [URL] = []

        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return found
        }

        for entry in entries {
            let name = entry.lastPathComponent
            if skipDirs.contains(name) { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // Skip the harness config dir since we already check it explicitly
            if name == claudeDir.lastPathComponent { continue }

            let candidate = entry.appendingPathComponent(memFile)
            if fm.fileExists(atPath: candidate.path) && !exclude.contains(candidate.path) {
                found.append(candidate)
            }

            found.append(contentsOf: findClaudeMdRecursive(in: entry, currentDepth: currentDepth + 1, maxDepth: maxDepth, exclude: exclude))
        }

        return found
    }

    // MARK: - CLAUDE.md Linting

    func lintClaudeMd(_ fileURL: URL, projectRoot: String?, homeDir: String) -> [LintResult] {
        let memFile = workspace.capabilities.memoryFileName ?? "instructions file"
        var results: [LintResult] = []
        let path = fileURL.path
        let display = makeDisplayPath(for: path, projectRoot: projectRoot, homeDir: homeDir)

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return results
        }

        let lines = content.components(separatedBy: "\n")
        let lineCount = lines.count

        // CMD001: >200 lines
        if lineCount > 200 {
            results.append(LintResult(
                severity: .warning,
                checkId: .CMD001,
                filePath: path,
                message: "\(memFile) has \(lineCount) lines, exceeding 200. Large files may dilute instruction priority.",
                fix: "Split into focused rules files with glob-scoped paths.",
                displayPath: display
            ))
        }

        // CMD002: >100 lines without rules directory
        if lineCount > 100 {
            let parentDir = fileURL.deletingLastPathComponent()
            // Check if there's a rules/ directory relative to where this memory file lives
            let rulesDir: URL
            if parentDir.lastPathComponent == claudeDir.lastPathComponent {
                rulesDir = parentDir.appendingPathComponent("rules")
            } else {
                rulesDir = claudeDir.appendingPathComponent("rules")
            }
            var isDir: ObjCBool = false
            let hasRules = fm.fileExists(atPath: rulesDir.path, isDirectory: &isDir) && isDir.boolValue
            if !hasRules {
                results.append(LintResult(
                    severity: .info,
                    checkId: .CMD002,
                    filePath: path,
                    message: "\(memFile) has \(lineCount) lines but no rules/ directory exists. Rules files let you scope instructions to specific file types.",
                    fix: "Create a rules/ directory and move file-type-specific instructions into scoped rule files.",
                    displayPath: display
                ))
            }
        }

        // CMD003: file-type patterns mentioned 3+ times
        let fileTypePattern = "\\*\\.[a-zA-Z0-9]+"
        var extensionCounts: [String: Int] = [:]
        for line in lines {
            if let _ = line.range(of: fileTypePattern, options: .regularExpression) {
                var searchStart = line.startIndex
                while let matchRange = line.range(of: fileTypePattern, options: .regularExpression, range: searchStart..<line.endIndex) {
                    let ext = String(line[matchRange])
                    extensionCounts[ext, default: 0] += 1
                    searchStart = matchRange.upperBound
                }
            }
        }
        let frequentExtensions = extensionCounts.filter { $0.value >= 3 }.map(\.key).sorted()
        if !frequentExtensions.isEmpty {
            results.append(LintResult(
                severity: .warning,
                checkId: .CMD003,
                filePath: path,
                message: "File-type patterns appear frequently: \(frequentExtensions.joined(separator: ", ")). These instructions may work better as scoped rules.",
                fix: "Move file-type-specific instructions into .claude/rules/ files with 'paths' frontmatter targeting those extensions.",
                displayPath: display
            ))
        }

        // CMD006: unclosed code blocks (odd number of ``` fences)
        var fenceCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                fenceCount += 1
            }
        }
        if fenceCount % 2 != 0 {
            results.append(LintResult(
                severity: .error,
                checkId: .CMD006,
                filePath: path,
                message: "Unclosed code block detected (\(fenceCount) fence markers found, expected even count). This can cause \(harness) to misparse instructions.",
                fix: "Add a closing ``` fence to balance all code blocks.",
                displayPath: display
            ))
        }

        return results
    }

    // MARK: - Commands Deprecation

    func checkCommandsDeprecation(projectRoot: String) -> [LintResult] {
        let commandsDir = claudeDir.appendingPathComponent("commands")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: commandsDir.path, isDirectory: &isDir), isDir.boolValue {
            return [LintResult(
                severity: .warning,
                checkId: .CMD_DEPRECATE,
                filePath: commandsDir.path,
                message: ".claude/commands/ directory exists. Custom commands have been superseded by skills in recent Claude Code versions.",
                fix: "Migrate commands to .claude/skills/ directories with SKILL.md files.",
                displayPath: ".claude/commands/"
            )]
        }
        return []
    }

    // MARK: - @import Chain Depth

    func checkImportDepth(projectRoot: String, claudeMdFiles: [URL], homeDir: String) -> [LintResult] {
        var results: [LintResult] = []

        for file in claudeMdFiles {
            let depth = measureImportDepth(from: file, visited: [], maxHops: 6)
            if depth > 5 {
                let display = makeDisplayPath(for: file.path, projectRoot: projectRoot, homeDir: homeDir)
                results.append(LintResult(
                    severity: .warning,
                    checkId: .CMD_IMPORT,
                    filePath: file.path,
                    message: "@import chain from this file reaches \(depth) hops deep, exceeding the recommended limit of 5.",
                    fix: "Flatten the import chain by consolidating intermediate files or removing unnecessary imports.",
                    displayPath: display
                ))
            }
        }

        return results
    }

    func measureImportDepth(from fileURL: URL, visited: [String], maxHops: Int) -> Int {
        guard !visited.contains(fileURL.path) else { return 0 }
        guard visited.count < maxHops + 1 else { return visited.count }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }

        let lines = content.components(separatedBy: "\n")
        var maxDepth = 0
        let parentDir = fileURL.deletingLastPathComponent()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match lines like "@path/to/file" or "@./relative/path"
            guard trimmed.hasPrefix("@") else { continue }
            let importPath = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !importPath.isEmpty else { continue }
            // Skip lines that look like email addresses or decorators
            if importPath.contains(" ") || importPath.hasPrefix("(") { continue }

            let resolvedURL: URL
            if importPath.hasPrefix("/") {
                resolvedURL = URL(fileURLWithPath: importPath)
            } else {
                resolvedURL = parentDir.appendingPathComponent(importPath).standardized
            }

            guard fm.fileExists(atPath: resolvedURL.path) else { continue }

            var newVisited = visited
            newVisited.append(fileURL.path)
            let depth = measureImportDepth(from: resolvedURL, visited: newVisited, maxHops: maxHops)
            maxDepth = max(maxDepth, depth + 1)
        }

        return maxDepth
    }
}
