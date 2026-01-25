# Ukiryu - Platform-Adaptive Command Execution Framework

## Project Name: Ukiryu (浮流)

**Ukiryu** (pronounced *oo-kee-ryoo*, 浮流) means "floating flow" in Japanese:

* **Floating** (浮) - The framework *adapts* to different implementations, platforms, and shells. It doesn't force a single way of working—instead, it flexibly accommodates the unique characteristics of each command-line tool.

* **Flow** (流) - The framework *unifies* diverse external tools into a consistent Ruby API. Like streams converging into a river, Ukiryu brings together Inkscape, Ghostscript, ImageMagick, Git, Docker, and countless other tools under one consistent interface.

---

## Executive Summary

Ukiryu is a Ruby framework for creating robust, cross-platform wrappers around external command-line tools through declarative YAML profiles. **Ukiryu turns external CLIs into Ruby APIs** with explicit type safety, shell detection, and platform profiles—no hidden magic, no silent fallbacks.

### Two-Repository Architecture

Ukiryu consists of two separate repositories:

```
┌─────────────────────────────────────────────────────────────────────┐
│  ukiryu/ukiryu (Core Framework)                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Ruby Gem: Framework Logic                                        │ │
│  │                                                                  │ │
│  │ - Shell detection (EXPLICIT: bash, zsh, powershell, cmd)       │ │
│  │ - Shell escaping (each shell knows its own rules)              │ │
│  │ - Type validation & conversion                                  │ │
│  │ - Command execution (timeout, error handling)                   │ │
│  │ - Profile selection (EXACT matching on platform+shell+version) │ │
│  │ - Environment variable management                               │ │
│  │ - YAML profile loader                                           │ │
│  │ - Version detection                                              │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  gem: ukiryu                                                          │
│  Zero dependencies (Ruby stdlib only)                                  │
└─────────────────────────────────────────────────────────────────────┘
                            │ loads
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ukiryu/register (Tool Register)                                     │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ YAML Profiles: Tool Definitions                                 │ │
│  │                                                                  │ │
│  │ tools/inkscape/1.0.yaml    tools/ghostscript/10.0.yaml           │ │
│  │ tools/imagemagick/7.0.yaml  tools/git/2.45.yaml                 │ │
│  │ tools/docker/25.0.yaml      tools/ffmpeg/7.0.yaml                │ │
│  │ ... (community-contributed)                                       │ │
│  │                                                                  │
│  │ schemas/*.yaml.schema      (YAML Schema validation)             │ │
│  │ docs/*.adoc                (AsciiDoc documentation)              │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  gem: ukiryu-register (optional, can use as git repo)                  │
│  Validates with: json-schema gem                                         │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Two Repositories?

| Aspect | Single Repo | Two Repos (Ukiryu) |
|--------|-----------|-------------------|
| **Release cycle** | Framework + tools together | Framework independent of tool updates |
| **Contributors** | Developers only | Anyone can add tools (no Ruby needed) |
| **Maintenance** | Code changes for new tools | YAML file changes for new tools |
| **Validation** | Test framework | Validate YAML against schema |
| **Discovery** | Gem update | `git pull` on register |
| **Flexibility** | Coupled | Decoupled - use custom registries |

---

## The Vision: Ukiryu as "Reverse Thor" for External Executables

### The Thor Model (for context)

Thor turns Ruby methods into CLI commands:

```ruby
class MyCLI < Thor
  desc "greet NAME", "Say hello"
  option :loud
  def greet(name)
    puts "Hello #{name}!"
  end
end

# Generates CLI:
# mycli greet Alice --loud
```

### The Ukiryu Model (Our Approach)

Ukiryu turns external CLI commands into Ruby methods:

```ruby
# Load tool profiles from register
Ukiryu::Register.load_from("ukiryu/register")

# Get the tool
inkscape = Ukiryu::Tool.get("inkscape")

# Use like a Ruby API
inkscape.export(
  inputs: ["diagram.svg"],
  output: "diagram.pdf",
  format: :pdf,
  plain: true
)
# CLI: inkscape --export-filename=diagram.pdf --export-type pdf --export-plain-svg diagram.svg
```

**The key insight:** Just as Thor provides a DSL to define a CLI, Ukiryu provides a YAML DSL to define a Ruby wrapper around a CLI. Ukiryu becomes the bridge between your Ruby code and external tools, handling all platform differences explicitly.

**"Floating"** - Ukiryu adapts to each tool's unique characteristics (different option formats, argument orders, version behaviors).

**"Flow"** - Ukiryu unifies diverse tools into one consistent Ruby API.

---

## The Need

### Problem: Four Layers of Cross-Platform Complexity

#### Layer 1: Executable Discovery

| Platform | Inkscape Binary | Ghostscript Binary |
|----------|-----------------|-------------------|
| Windows | `inkscape.exe` | `gswin64c.exe` |
| macOS | `inkscape` (app bundle) | `gs` |
| Linux | `inkscape` | `gs` |

**Search strategy:**
- Unix: `ENV["PATH"]` is sufficient (tools installed in standard locations)
- Windows: `ENV["PATH"]` plus common installation directories
  - `C:/Program Files/Tool/`
  - `C:/Program Files (x86)/Tool/`
  - App bundles on macOS

#### Layer 2: Shell Escaping (CRITICAL!)

Each shell has fundamentally different escaping rules:

**Bash/Zsh:**
```bash
# Single quotes: literal (no escaping inside)
echo 'Hello $USER'          # => Hello $USER

# Double quotes: variable expansion
echo "Hello $USER"          # => Hello alice

# Backslash escaping inside double quotes
echo "Path: \"file\""      # => Path: "file"
```

**PowerShell:**
```powershell
# Single quotes: literal
Write-Host 'Hello $ENV:USER' # => Hello $ENV:USER

# Double quotes: variable expansion
Write-Host "Hello $ENV:USER" # => Hello alice

# Backtick escaping inside double quotes
Write-Host "Path: `"`         # => Path: "
```

**cmd.exe:**
```cmd
# Caret is escape character
echo ^^%USERNAME%^           # alice (caret escapes, % expands)
```

#### Layer 3: Command Syntax Differences

| Tool Aspect | Unix | Windows (some ports) |
|------------|------|-------------------|
| Long options | `--option=value` | `/Option:value` |
| Short options | `-o value` | `/Ovalue` |
| Output specification | `--output=file.pdf` | `/Output:file.pdf` |
| Flags | `--plain` | `/plain` |
| Path format | `/usr/bin/file` | `C:\Program Files\file` |

#### Layer 4: Type Safety & Validation

| Issue | Example | Consequence |
|-------|---------|--------------|
| Wrong shell escaping | Unescaped `$USER` | Security vulnerability |
| Wrong path for platform | `/usr/bin/file` on Windows | "file not found" |
| Invalid enum value | `format: :docx` | Tool fails with cryptic error |
| Out-of-range integer | `quality: 150` | Tool uses default or fails |

### Current Solutions Are Insufficient

| Solution | Problems |
|----------|----------|
| `Open3.capture3` | No types, no escaping, no platform awareness |
| `Shellwords.escape` | Bash-only, doesn't handle cmd/PowerShell |
| `posix-spawn` | Unix-only |
| **Each library reimplements everything poorly** | Incomplete, inconsistent, error-prone |

---

## What Ukiryu Does

Ukiryu provides a complete execution pipeline with **explicit** (no fallbacks):

```
Ruby API Call (Typed Parameters)
    ↓
Type Validation (Semantic: paths, URIs, ranges, enums)
    ↓ (Error if invalid)
Shell Detection (EXPLICIT or raise error)
    ↓ (Error if unknown)
Profile Selection (EXACT match on platform+shell+version)
    ↓ (Error if no match)
Command Building (Shell-specific escaping)
    ↓
Execution (Platform-specific methods)
    ↓
Result Parsing
```

**Key principle:** Explicit over implicit. If Ukiryu can't determine shell or profile, it raises a clear error rather than guessing.

---

## Architecture: Hybrid Approach (Ruby Framework + YAML Profiles)

### Two-Layer Design

Ukiryu separates **framework logic** (Ruby) from **tool definitions** (YAML):

```
┌─────────────────────────────────────────────────────────────┐
│                    UKIRYU FRAMEWORK (Ruby)                  │
│  - Shell detection & escaping                               │
│  - Type validation & conversion                            │
│  - Execution & timeout handling                             │
│  - Profile selection algorithm                             │
│  - Environment variable management                          │
└───────────────────────────┬─────────────────────────────────┘
                            │ loads
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 TOOL PROFILES (YAML Register)              │
│  - inkscape.yaml (all versions)                            │
│  - ghostscript.yaml (all versions)                         │
│  - imagemagick.yaml (all versions)                         │
│  - git.yaml (all subcommands)                              │
│  - ... (community-contributed)                             │
└─────────────────────────────────────────────────────────────┘
```

### Why YAML Profiles?

| Aspect | Ruby DSL | YAML Profiles |
|--------|----------|---------------|
| **New tool support** | Requires code + release | Add YAML file |
| **Version update** | Requires code + release | Update YAML |
| **Maintenance** | Developers only | Anyone can edit |
| **Validation** | Compile-time | Load-time |
| **Distribution** | Gem releases | Separate register |
| **Community** | Pull requests | PRs to register repo |

### YAML Profile Structure

```yaml
# profiles/inkscape.yaml

name: inkscape
aliases:
  - inkscapecom
  - ink

version_detection:
  command: "--version"
  pattern: "Inkscape (\\d+\\.\\d+)"
  modern_threshold: "1.0"

search_paths:
  windows:
    - "C:/Program Files/Inkscape*/inkscape.exe"
  macos:
    - "/Applications/Inkscape.app/Contents/MacOS/inkscape"
  # Unix: rely on PATH only

profiles:
  # Modern Inkscape (1.0+) on Unix
  - name: modern_unix
    platforms: [macos, linux]
    shells: [bash, zsh, fish, sh]
    version: ">= 1.0"
    option_style: double_dash_equals
    commands:
      export:
        arguments:
          - name: inputs
            type: file
            variadic: true
            position: last
            min: 1

        options:
          - name: output
            type: file
            cli: "--export-filename="
            format: double_dash_equals

          - name: format
            type: symbol
            values: [svg, png, ps, eps, pdf, emf, wmf, xaml]
            cli: "--export-type"
            format: double_dash_space
            separator: " "

          - name: dpi
            type: integer
            cli: "-d"
            format: single_dash_space
            separator: " "

          - name: quality
            type: integer
            cli: "-d"
            range: [0, 100]

          - name: export_background
            type: string
            cli: "--export-background="

        flags:
          - name: plain
            cli: "--export-plain-svg"
            cli_short: "-l"

          - name: export_text_to_path
            cli: "--export-text-to-path"
            cli_short: "-T"

        env_vars:
          - name: DISPLAY
            value: ""
            platforms: [macos, linux]

      query:
        arguments:
          - name: input
            type: file
            required: true

        flags:
          - name: width
            cli: "--query-width"
            cli_short: "-W"

          - name: height
            cli: "--query-height"
            cli_short: "-H"

          - name: x
            cli: "--query-x"
            cli_short: "-X"

          - name: y
            cli: "--query-y"
            cli_short: "-Y"

  # Modern Inkscape (1.0+) on Windows PowerShell
  - name: modern_windows_powershell
    platforms: [windows]
    shells: [powershell]
    version: ">= 1.0"
    option_style: double_dash_equals
    # Same command structure as modern_unix
    # (inherits from base profile)
    inherits: modern_unix

  # Modern Inkscape (1.0+) on Windows cmd
  - name: modern_windows_cmd
    platforms: [windows]
    shells: [cmd]
    version: ">= 1.0"
    option_style: slash_space
    commands:
      export:
        # Same structure but different CLI syntax
        options:
          - name: output
            type: file
            cli: "/ExportFilename"
            format: slash_space
            separator: " "
```

### YAML Profile Register

**Register structure:**
```
ukiryu-register/
├── tools/
│   ├── inkscape/
│   │   ├── 1.0.yaml
│   │   ├── 0.92.yaml
│   │   └── 0.9.yaml
│   ├── ghostscript/
│   │   ├── 10.0.yaml
│   │   ├── 9.5.yaml
│   │   └── 9.0.yaml
│   ├── imagemagick/
│   │   ├── 7.0.yaml
│   │   └── 6.0.yaml
│   ├── git/
│   │   ├── 2.45.yaml
│   │   └── 2.40.yaml
│   ├── docker/
│   │   ├── 25.0.yaml
│   │   └── 24.0.yaml
│   └── ...
├── schemas/
│   ├── tool-profile.yaml.schema
│   ├── command-definition.yaml.schema
│   └── register.yaml.schema
├── docs/
│   ├── inkscape.adoc
│   ├── ghostscript.adoc
│   ├── contributing.adoc
│   └── register.adoc
├── lib/
│   └── ukiryu/
│       └── register.rb           # Register helper library
├── Gemfile                         # json-schema gem
├── Rakefile                        # Validation tasks
└── README.adoc
```

**Version file naming:**
- Use semantic version: `1.0.yaml`, `0.9.5.yaml`
- Multiple profiles per version (platform/shell combos) in one file
- Register selects newest compatible version

**Loading profiles in Ukiryu:**
```ruby
# Load from register
Ukiryu::Register.load_from("/path/to/ukiryu/register")

# Or load from gem-builtin profiles
Ukiryu::Register.load_builtins

# Load specific tool/version
Ukiryu::Register.load_tool("inkscape", version: "1.0")
Ukiryu::Register.load_tool("inkscape")  # Auto-detect latest

# Use the tool
inkscape = Ukiryu::Tool.get("inkscape")
inkscape.export(
  inputs: ["diagram.svg"],
  output: "diagram.pdf",
  format: :pdf
)
```

**Schema validation with `json-schema` gem:**
```ruby
# In register Rakefile
require 'json-schema'

namespace :validate do
  task :all do
    # Validate all YAML files against schemas
    Dir.glob("tools/*/*.yaml").each do |file|
      schema = JSON::Schema.new(parse_schema("schemas/tool-profile.yaml.schema"))
      schema.validate(YAML.load_file(file))
    end
  end
end
```

### Profile Inheritance

Avoid duplication with profile inheritance:

```yaml
# ghostscript/10.0.yaml
name: ghostscript
version: "10.0"
display_name: Ghostscript 10.0
homepage: https://www.ghostscript.com/

profiles:
  # Base Ghostscript profile
  - name: base_ghostscript
    commands:
      convert:
        options:
          - name: device
            type: symbol
            values: [pdfwrite, eps2write, png16m, jpeg]
            cli: "-sDEVICE="

          - name: output
            type: file
            cli: "-sOutputFile="

        flags:
          - name: safer
            cli: "-dSAFER"

          - name: quiet
            cli: "-q"

  # Unix variant
  - name: unix
    platforms: [macos, linux]
    shells: [bash, zsh, fish, sh]
    inherits: base_ghostscript
    # Add Unix-specific options
    commands:
      convert:
        options:
          - name: lib_paths
            type: array
            of: file
            cli: "-I"
            separator: " "

  # Windows variant
  - name: windows
    platforms: [windows]
    shells: [powershell, cmd]
    inherits: base_ghostscript
    # Same structure, shell handles escaping
```

### Real-World: Inkscape Complete YAML Profile

```yaml
# ukiryu-register/tools/inkscape.yaml

name: inkscape
display_name: Inkscape Vector Graphics Editor
homepage: https://inkscape.org/
version_detection:
  command: "--version"
  pattern: "Inkscape (\\d+\\.\\d+)"
  modern_threshold: "1.0"

search_paths:
  windows:
    - "C:/Program Files/Inkscape*/inkscape.exe"
    - "C:/Program Files (x86)/Inkscape*/inkscape.exe"
  macos:
    - "/Applications/Inkscape.app/Contents/MacOS/inkscape"
  # Unix: PATH only, no hardcoded paths

aliases: [inkscapecom, ink]

timeout: 90
terminate_signal: TERM

profiles:
  # ============================================
  # Modern Inkscape (1.0+) - Unix
  # ============================================
  - name: modern_unix
    display_name: Modern Inkscape on Unix
    platforms: [macos, linux]
    shells: [bash, zsh, fish, sh]
    version: ">= 1.0"
    option_style: double_dash_equals
    escape_quotes: single

    commands:
      # ============================================
      # COMMAND: export
      # ============================================
      export:
        description: "Export document to different format"
        usage: "inkscape [OPTIONS] input1.svg [input2.svg ...]"

        arguments:
          - name: inputs
            type: file
            variadic: true
            position: last
            min: 1
            description: "Input file(s)"

        options:
          # Output file
          - name: output
            type: file
            cli: "--export-filename="
            format: double_dash_equals
            description: "Output filename"
            required: true

          # Export format
          - name: format
            type: symbol
            cli: "--export-type"
            format: double_dash_space
            separator: " "
            values: [svg, png, ps, eps, pdf, emf, wmf, xaml]
            description: "Output format"

          # Multiple export types (comma-separated)
          - name: export_types
            type: array
            of: symbol
            cli: "--export-type="
            separator: ","
            values: [svg, png, ps, eps, pdf, emf, wmf, xaml]
            description: "Multiple export formats"

          # DPI for bitmap export
          - name: dpi
            type: integer
            cli: "-d"
            format: single_dash_space
            separator: " "
            range: [1, 10000]
            description: "Resolution for bitmaps (default: 96)"

          # Width
          - name: width
            type: integer
            cli: "--export-width="
            description: "Bitmap width in pixels"

          # Height
          - name: height
            type: integer
            cli: "--export-height="
            description: "Bitmap height in pixels"

          # Export area
          - name: area
            type: string
            cli: "--export-area="
            description: "Export area (x0:y0:x1:y1)"

          # Export page
          - name: export_page
            type: string
            cli: "--export-page="
            description: "Page number to export"

          # Background color
          - name: background
            type: string
            cli: "--export-background="
            description: "Background color"

          # Background opacity
          - name: background_opacity
            type: float
            cli: "--export-background-opacity="
            range: [0.0, 1.0]
            description: "Background opacity (0.0 to 1.0)"

          # Object IDs to export (semicolon-separated)
          - name: export_ids
            type: array
            of: string
            cli: "--export-id="
            separator: ";"
            description: "Object IDs to export"

        flags:
          # Plain SVG export
          - name: plain
            cli: "--export-plain-svg"
            cli_short: "-l"
            description: "Remove Inkscape-specific attributes"

          # Export area = page
          - name: area_page
            cli: "--export-area-page"
            cli_short: "-C"
            description: "Export area is page"

          # Export area = drawing
          - name: area_drawing
            cli: "--export-area-drawing"
            cli_short: "-D"
            description: "Export area is drawing"

          # Text to path
          - name: text_to_path
            cli: "--export-text-to-path"
            cli_short: "-T"
            description: "Convert text to paths"

          # Ignore filters
          - name: ignore_filters
            cli: "--export-ignore-filters"
            description: "Render without filters"

          # Vacuum defs
          - name: vacuum_defs
            cli: "--vacuum-defs"
            description: "Remove unused definitions"

        env_vars:
          - name: DISPLAY
            value: ""
            platforms: [macos, linux]
            description: "Disable display for headless operation"

      # ============================================
      # COMMAND: query
      # ============================================
      query:
        description: "Query document dimensions"
        usage: "inkscape --query-width/--query-height input.svg"

        arguments:
          - name: input
            type: file
            required: true
            description: "Input file"

        flags:
          - name: width
            cli: "--query-width"
            cli_short: "-W"
            description: "Query width"

          - name: height
            cli: "--query-height"
            cli_short: "-H"
            description: "Query height"

          - name: x
            cli: "--query-x"
            cli_short: "-X"
            description: "Query X coordinate"

          - name: y
            cli: "--query-y"
            cli_short: "-Y"
            description: "Query Y coordinate"

        parse_output:
          type: hash
          pattern: "key:\\s*value"

  # ============================================
  # Modern Inkscape (1.0+) - Windows PowerShell
  # ============================================
  - name: modern_windows_powershell
    display_name: Modern Inkscape on Windows (PowerShell)
    platforms: [windows]
    shells: [powershell]
    version: ">= 1.0"
    option_style: double_dash_equals
    inherits: modern_unix
    # Inherits all commands, shell handles escaping

  # ============================================
  # Modern Inkscape (1.0+) - Windows cmd
  # ============================================
  - name: modern_windows_cmd
    display_name: Modern Inkscape on Windows (cmd)
    platforms: [windows]
    shells: [cmd]
    version: ">= 1.0"
    option_style: slash_space
    # Need to redefine commands for different option syntax
    commands:
      export:
        arguments:
          - name: inputs
            type: file
            variadic: true
            position: last
            min: 1

        options:
          - name: output
            type: file
            cli: "/ExportFilename"
            format: slash_space
            separator: " "

          # ... other options with /Option syntax

        flags:
          - name: plain
            cli: "/Plain"
```

### Schema Validation

YAML profiles are validated against YAML Schema using the `json-schema` gem:

```yaml
# schemas/tool-profile.yaml.schema
---
$schema: "http://json-schema.org/draft-07/schema#"
$title: "Ukiryu Tool Profile"
$description: "Schema for Ukiryu tool command profiles"
$type: "object"
$required:
  - name
  - version
  - display_name
  - profiles

properties:
  name:
    type: string
    description: "Tool command name (e.g., 'inkscape', 'gs')"

  version:
    type: string
    description: "Tool semantic version (e.g., '1.0', '10.0.0')"

  display_name:
    type: string
    description: "Human-readable tool name"

  homepage:
    type: string
    format: uri
    description: "Tool homepage URL"

  aliases:
    type: array
    items:
      type: string
    description: "Alternative command names"

  search_paths:
    type: object
    properties:
      windows:
        type: array
        items:
          type: string
      macos:
        type: array
        items:
          type: string
      # Unix: no hardcoded paths, rely on PATH

  version_detection:
    type: object
    $required:
      - command
      - pattern
    properties:
      command:
        type: string
      pattern:
        type: string
      modern_threshold:
        type: string

  profiles:
    type: array
    items:
      type: object
      $required:
        - name
        - platforms
        - shells
        - commands
      properties:
        name:
          type: string

        platforms:
          type: array
          items:
            type: string
            enum: [windows, macos, linux]

        shells:
          type: array
          items:
            type: string
            enum: [bash, zsh, fish, sh, powershell, cmd]

        version:
          type: string
          description: "Version constraint (e.g., '>= 1.0', '< 2.0')"

        inherits:
          type: string
          description: "Profile name to inherit from"

        option_style:
          type: string
          enum: [double_dash_equals, double_dash_space,
                 single_dash_equals, single_dash_space,
                 slash_space, slash_colon]

        commands:
          type: object
          patternProperties:
            "^[a-z_]+$":
              type: object
              $required:
                - arguments
              properties:
                description:
                  type: string

                usage:
                  type: string

                arguments:
                  type: array
                  items:
                    type: object
                    $required:
                      - name
                      - type
                    properties:
                      name:
                        type: string

                      type:
                        type: string
                        enum: [file, string, integer, float, symbol, boolean, uri, datetime, hash, array]

                      variadic:
                        type: boolean

                      min:
                        type: integer

                      position:
                        oneOf:
                          - type: integer
                          - type: string
                            enum: [last]

                      required:
                        type: boolean

                      values:
                        type: array
                        items:
                          type: string

                      range:
                        type: array
                        items:
                          type: number
                        minItems: 2
                        maxItems: 2

                      separator:
                        type: string

                      default:
                        type: boolean

                      description:
                        type: string

                options:
                  type: array
                  items:
                    type: object
                    $required:
                      - name
                      - cli
                    properties:
                      name:
                        type: string

                      type:
                        type: string
                        enum: [file, string, integer, float, symbol, boolean, uri, datetime, hash, array]

                      cli:
                        type: string

                      cli_short:
                        type: string

                      format:
                        type: string
                        enum: [double_dash_equals, double_dash_space,
                               single_dash_equals, single_dash_space,
                               slash_space, slash_colon]

                      separator:
                        type: string

                      values:
                        type: array
                        items:
                          type: string

                      range:
                        type: array
                        items:
                          type: number
                        minItems: 2
                        maxItems: 2

                      size:
                        oneOf:
                          - type: integer
                          - type: array
                            items:
                              type: integer

                      required:
                        type: boolean

                      default:
                        type: [string, integer, float, boolean]

                      description:
                        type: string

                flags:
                  type: array
                  items:
                    type: object
                    $required:
                      - name
                      - cli
                    properties:
                      name:
                        type: string

                      cli:
                        type: string

                      cli_short:
                        type: string

                      default:
                        type: boolean

                      description:
                        type: string

                env_vars:
                  type: array
                  items:
                    type: object
                    $required:
                      - name
                    properties:
                      name:
                        type: string

                      value:
                        type: string

                      from:
                        type: string

                      default:
                        type: string

                      platforms:
                        type: array
                        items:
                          type: string

                      description:
                        type: string

                parse_output:
                  type: object
                  properties:
                    type:
                      type: string
                      enum: [hash, array, string, integer]

                    pattern:
                      type: string

                    format:
                      type: string
```

**Validation with `json-schema` gem:**

```ruby
# In register Rakefile
require 'json-schema'
require 'yaml'

namespace :validate do
  desc "Validate all tool profiles against schema"
  task :tools do
    schema = JSON::Schema.new(YAML.load_file('schemas/tool-profile.yaml.schema'))

    Dir.glob('tools/*/*.yaml').each do |file|
      puts "Validating #{file}..."
      profile = YAML.load_file(file)
      schema.validate(profile)
      puts "  ✓ Valid"
    end
  rescue JSON::Schema::ValidationError => e
    puts "  ✗ Validation failed: #{e.message}"
    exit 1
  end

  desc "Validate schema files themselves"
  task :schemas do
    # Verify schemas are valid YAML Schema
    Dir.glob('schemas/*.yaml.schema').each do |file|
      puts "Validating schema #{file}..."
      schema = YAML.load_file(file)
      puts "  ✓ Valid YAML Schema"
    end
  end

  task all: [:schemas, :tools]
end
```

### Usage Examples

```ruby
# Load from register
Ukiryu::Register.load_from("~/.ukiryu/register")

# Or load from gem
Ukiryu::Register.load_builtins

# Get tool
inkscape = Ukiryu::Tool.get("inkscape")

# Detect platform, shell, version automatically
# (or configure explicitly)
inkscape.configure(
  platform: :macos,
  shell: :zsh
)

# Export command
inkscape.export(
  inputs: ["diagram.svg"],
  output: "diagram.pdf",
  format: :pdf,
  plain: true,
  dpi: 300
)

# Query command
result = inkscape.query(
  input: "diagram.svg",
  width: true,
  height: true
)
# => { width: 1024, height: 768 }
```

---

## Core DSL Design (For Custom Tools)

For tools not in the register, users can still use Ruby DSL:

### Tool Declaration

```ruby
class MyToolWrapper < Ukiryu::Wrapper
  tool "mytool" do
    # ---------- EXECUTABLE ----------

    # Names to try (tried in order until one is found)
    names "mytool", "mt", "mytool-cli"

    # Search paths (always includes ENV["PATH"])
    # Platform-specific additions:
    search_paths do
      # Windows-specific
      on_windows do
        "C:/Program Files/MyTool/*/mytool.exe"
        "#{ENV['PROGRAMFILES']}/MyTool/mytool.exe"
      end

      # macOS app bundles
      on_macos do
        "/Applications/MyTool.app/Contents/MacOS/mytool"
      end

      # Unix (no hardcoded paths - rely on PATH)
      # on_unix do
        # No hardcoded paths - rely on PATH only
      end
    end

    # ---------- VERSION ----------

    detect_version do
      run "--version"
      match /MyTool (\d+\.\d+\.\d+)/
      modern "2.0.0"
    end

    # ---------- PROFILES ----------

    # Each profile matches: platform + shell + version
    # All three must match for profile to be selected

    # Modern (2.0+) on Bash/Zsh on Unix
    profile :modern_unix_bash,
            platform: [:macos, :linux],
            shell: [:bash, :zsh],
            version: ">= 2.0" do
      arguments do |params|
        [params.input, params.option_as_cli("--format="), params.flag_as_flag(:plain)]
      end
    end

    # Modern on PowerShell on Windows
    profile :modern_windows_powershell,
            platform: :windows,
            shell: :powershell,
            version: ">= 2.0" do
      arguments do |params|
        [params.input, params.option_as_cli("/Format:"), params.flag_as_flag("/Plain")]
      end
    end

    # Legacy on cmd on Windows
    profile :legacy_windows_cmd,
            platform: :windows,
            shell: :cmd,
            version: "< 2.0" do
      arguments do |params|
        [params.input, params.option_as_cli("/Format:"), params.flag_as_flag("/Plain")]
      end
    end

    # ---------- GLOBAL DEFAULTS ----------

    timeout 90
    terminate_with :TERM, after: 5, then: :KILL
    on_windows { terminate_with :KILL }  # Windows only supports KILL reliably
    shell :bash  # Default shell detection fallback
  end
end
```

### Type System

All parameter types with shell escaping behavior:

| Type | Ruby Type | Shell Escaping | Example |
|------|-----------|----------------|---------|
| `:file` | String path | Platform-specific | `'/path/file.pdf'` (Bash) |
| `:string` | String | Fully escaped | `'Hello $USER'` (Bash, literal) |
| `:integer` | Integer | No escaping (numeric) | `95` |
| `:float` | Float | No escaping (numeric) | `95.5` |
| `:symbol` | Symbol | No escaping (alnum) | `pdf` |
| `:boolean` | Boolean | Flag or value | `--plain` added/not added |
| `:uri` | String | Fully escaped | `'https://example.com'` |
| `:datetime` | DateTime/String | Formatted then escaped | `'2025-01-21'` |
| `:hash` | Hash | Recursively escaped/merged | `{:key => "value"}` |

### Parameter Definitions

```ruby
command :convert do
  # POSITIONAL argument (order matters!)
  argument :input,
          type: :file,
          position: 1,
          required: true

  # OPTION (named with value)
  option :format,
          type: :symbol,
          values: [:pdf, :eps, :svg],
          cli: "--format=",
          required: true

  # FLAG (boolean, presence = true)
  flag :plain,
        cli: "--plain",
        default: false

  # OUTPUT (where output goes)
  output :file,
        type: :file,
        via: :option,  # Uses --export-filename= option
        cli: "--export-filename="
end
```

### Type Validation Examples

| Type | Input | Validation | Shell Escaped As |
|------|-------|------------|------------------|
| `:file` | `"file.pdf"` | File exists? | `'file.pdf'` (Bash) |
| `:string` | `"Hello World"` | Not empty | `'Hello World'` |
| `:integer` | `95` | In 1..100 | `95` (no escape) |
| `:symbol` | `:pdf` | In whitelist | `pdf` (no escape) |
| `:boolean` | `true` | N/A | `--plain` added |
| `:uri` | `https://example.com` | Valid URI | `'https://example.com'` |
| `:datetime` | `DateTime.now` | Parseable | `'2025-01-21'` |

---

## Shell Detection (EXPLICIT)

### Detection Algorithm

```ruby
module Ukiryu
  class Shell
    class << self
      def detect
        # Unix/macOS
        if unix?
          shell_from_env
        end

        # Windows
        if windows?
          detect_windows_shell
        end

        raise Ukiryu::UnknownShellError, <<~ERROR
Unable to detect shell automatically. Please configure explicitly:

  Ukiryu::Shell.configure do |config|
    config.shell = :bash  # or :powershell, :cmd, :zsh
  end

Current environment:
  Platform: #{RbConfig::CONFIG['host_os']}
  SHELL: #{ENV['SHELL']}
  PSModulePath: #{ENV['PSModulePATH']}
ERROR
      end

      private

      def unix?
        RbConfig::CONFIG['host_os'] !~ /mswin|mingw|windows/
      end

      def windows?
        Gem.win_platform?
      end

      def detect_windows_shell
        return :powershell if ENV['PSModulePath']
        return :bash if ENV['MSYSTEM'] || ENV['MINGW_PREFIX']
        return :bash if ENV['WSL_DISTRO']
        return :cmd  # Default Windows shell
      end

      def shell_from_env
        return :bash if ENV['SHELL'].end_with?('bash')
        return :zsh if ENV['SHELL'].end_with?('zsh')
        return :fish if ENV['SHELL'].end_with?('fish')
        return :sh if ENV['SHELL'].end_with?('sh')

        # Unknown shell in ENV - try to detect
        shell_path = ENV['SHELL']
        if File.executable?(shell_path)
          name = File.basename(shell_path)
          return name.to_sym
        end

        raise Ukiryu::UnknownShellError, "Unknown shell: #{ENV['SHELL']}"
      end
    end
  end
end
```

### Supported Shells

| Shell | Platform | Detection | Quote | Escape | Env Var |
|-------|----------|-----------|------|--------|---------|
| Bash | Unix/macOS/Linux | `$SHELL` ends with `bash` | `'str'` | `'\\''` | `$VAR` |
| Zsh | Unix/macOS/Linux | `$SHELL` ends with `zsh` | `'str'` | `'\\''` | `$VAR` |
| Fish | Unix/macOS/Linux | `$SHELL` ends with `fish` | `'str'` | `'\\''` | `$VAR` |
| Sh | Unix/minimal | `$SHELL` ends with `sh` | `'str'` | `'\\''` | `$VAR` |
| PowerShell | Windows | `ENV['PSModulePath']` exists | `'str'` | `` ` `` | `$ENV:NAME` |
| Cmd | Windows | Default on Windows | `"` | `^` | `%VAR%` |

### Shell Configuration

```ruby
# Global configuration
Ukiryu::Shell.configure do |config|
  config.shell = :powershell
end

# Per-tool configuration
tool "mytool" do
  shell :bash  # Force bash for this tool
end

# Per-execution override
result = execute(cmd, shell: :zsh)
```

---

## Command Profiles (EXACT Matching)

### Profile Matching Rules

**Rule 1: EXACT match on Platform + Shell**
- Must match both platform and shell exactly
- `platform: :windows, shell: :powershell` ≠ `platform: :windows, shell: :bash`

**Rule 2: Version compatibility**
- If tool is version 8.0 and profile exists for 7.0 → can use 7.0 profile
- Assumes backward compatibility within major versions

**Rule 3: No partial matches**
- If no exact profile matches → raise `Ukiryu::ProfileNotFoundError`
- No "fallback to generic" - explicit or fail

### Profile Declaration

```ruby
tool "inkscape" do

  # ---------- EXACT PROFILES ----------

  # macOS + Bash + Modern (1.0+)
  profile :macos_bash_modern,
          platform: :macos,
          shell: :bash,
          version: ">= 1.0" do
    # Define how to build command line from parameters
    arguments do |params|
      [
        params.input,                                    # Positional arg 1
        params.option_as_cli("--export-type="),           # Named option
        params.flag_as_flag(:plain)                    # Optional flag
      ]
    end
  end

  # Windows + PowerShell + Modern (1.0+)
  profile :windows_powershell_modern,
          platform: :windows,
          shell: :powershell,
          version: ">= 1.0" do
    arguments do |params|
      [
        params.input,
        params.option_as_cli("--export-type="),
        params.flag_as_flag(:plain)
      ]
    end

  # Windows + cmd + Legacy (< 1.0)
  profile :windows_cmd_legacy,
          platform: :windows,
          shell: :cmd,
          version: "< 1.0" do
    arguments do |params|
      [
        params.input,
        params.option_as_cli("--export-type="),
        params.flag_as_flag(:plain)
      ]
    end

  # Windows + Git Bash + Modern
  profile :windows_bash_modern,
          platform: :windows,
          shell: :bash,
          version: ">= 1.0" do
    arguments do |params|
      [
        params.input,
        params.option_as_cli("--export-type="),
        params.flag_as_flag(:plain)
      ]
    end
end
```

### Profile Selection Algorithm

```ruby
module Ukiryu
  class ProfileSelector
    class << self
      def select(tool_name, platform:, shell:, version:)
        profiles = profiles_for(tool_name)

        # Find EXACT matches
        matches = profiles.select do |profile|
          profile.platform == platform &&
          profile.shell == shell &&
          profile.satisfies_version?(version)
        end

        return matches.first if matches.any?

        # No exact match: try compatible versions
        compatible = profiles.select do |profile|
          profile.platform == platform &&
          profile.shell == shell &&
          profile.compatible_with?(version)
        end

        return compatible.first if compatible.any?

        # Nothing matches: raise error
        available = profiles.map(&:description).join(", ")
        raise ProfileNotFoundError, <<~ERROR
No matching profile found for:
  Tool: #{tool_name}
  Platform: #{platform}
  Shell: #{shell}
  Version: #{version}

Available profiles:
  #{available}

Please configure Ukiryu with the correct profile.
ERROR
      end
    end
  end
end
```

---

## Complete DSL Specification

### Tool Declaration

```ruby
class MyToolWrapper < Ukiryu::Wrapper
  tool "mytool" do
    # ---------- EXECUTABLE ----------

    # Names to try (tried in order until found)
    names "mytool", "mt", "mytool-cli"

    # Search paths (always includes ENV["PATH"])
    # Add platform-specific paths only if not in PATH
    search_paths do
      on_windows { "C:/Program Files/MyTool/*/mytool.exe" }
      on_macos { "/Applications/MyTool.app/Contents/MacOS/mytool" }
      # Unix: no hardcoded paths (rely on PATH)
    end

    # ---------- VERSION ----------

    detect_version do
      run "--version"
      match /MyTool (\d+\.\d+)/
      modern "2.0.0"
    end

    # ---------- PROFILES ----------

    # Define multiple profiles for different combos
    profile :modern_bash,
            platform: [:macos, :linux],
            shell: [:bash, :zsh],
            version: ">= 2.0" do
      option_style :double_dash
      separator "="
    end

    profile :legacy_cmd,
            platform: :windows,
            shell: :cmd,
            version: "< 2.0" do
      option_style :slash
      separator ":"
    end

    # ---------- GLOBAL DEFAULTS ----------

    timeout 90
    terminate_with :TERM, after: 5, then: :KILL
    shell :bash  # Default detection fallback
  end
end
```

---

## Option Format Variations

CLI tools use many different option formats. Ukiryu supports all common patterns:

### Format Types

| Format | Example | CLI Syntax | DSL Specification |
|--------|---------|------------|------------------|
| Double-dash equals | `--format=pdf` | `--flag=value` | `cli: "--format="` |
| Double-dash space | `--format pdf` | `--flag value` | `cli: "--format", separator: " "` |
| Single-dash equals | `-f=pdf` | `-f=value` | `cli: "-f="` |
| Single-dash space | `-f pdf` | `-f value` | `cli: "-f", separator: " "` |
| Windows slash | `/format pdf` | `/flag value` | `cli: "/format", separator: " "` |
| Single-letter flag | `-v` | Just the flag | `flag :verbose, cli: "-v"` |
| Combined flags | `-v -a -q` → `-vaq` | `-vaq` | Automatic for single-letter flags |
| Value in flag | `-r300` | Value embedded | `cli: "-r", value_position: :embedded` |

### Option Format DSL

```ruby
command :export do
  # Double-dash with equals (GNU style)
  option :format,
          type: :symbol,
          values: [:pdf, :eps, :svg],
          cli: "--format=",
          format: :double_dash_equals  # --format=pdf

  # Double-dash with space (POSIX long)
  option :dpi,
          type: :integer,
          cli: "--dpi",
          format: :double_dash_space,  # --dpi 96
          separator: " "

  # Single-dash short option
  option :quality,
          type: :integer,
          cli: "-q",
          format: :single_dash_equals,  # -q=95
          separator: "="

  # Windows-style slash
  option :output,
          type: :file,
          cli: "/Output",
          format: :slash_space,  # /Output file.pdf
          separator: " "
end
```

### Profile-Specific Option Formats

Different platforms/shells use different formats:

```ruby
tool "mytool" do
  # Unix/modern: double-dash equals
  profile :modern_unix,
          platform: [:macos, :linux],
          shell: [:bash, :zsh] do
    option_style :double_dash_equals
  end

  # Windows PowerShell: slash with space
  profile :windows_powershell,
          platform: :windows,
          shell: :powershell do
    option_style :slash_space
  end

  # Windows cmd: slash with colon
  profile :windows_cmd,
          platform: :windows,
          shell: :cmd do
    option_style :slash_colon
  end
end
```

### Real-World Inkscape Example

```ruby
class Inkscape < Ukiryu::Wrapper
  tool "inkscape" do
    names "inkscape", "inkscapecom"
    detect_version { run "--version"; match /Inkscape (\d+\.\d+)/ }
  end

  command :export do
    # Inkscape has MANY option formats!

    # Double-dash equals: --export-filename=out.pdf
    option :output,
            type: :file,
            cli: "--export-filename=",
            format: :double_dash_equals

    # Double-dash space: --export-type pdf
    option :format,
            type: :symbol,
            values: [:svg, :png, :ps, :eps, :pdf, :emf, :wmf, :xaml],
            cli: "--export-type",
            format: :double_dash_space,
            separator: " "

    # Single-letter with equals: -o=out.pdf (alias for --export-filename)
    option :output_short,
            type: :file,
            cli: "-o=",
            format: :single_dash_equals

    # Single-letter space: -d 96
    option :dpi,
            type: :integer,
            cli: "-d",
            format: :single_dash_space,
            separator: " "

    # Flag: --export-plain-svg
    flag :plain,
          cli: "--export-plain-svg"

    # Single-letter flag: -l (alias for --export-plain-svg)
    flag :plain_short,
          cli: "-l"

    # Variadic input files: inkscape [options] file1 [file2 ...]
    argument :inputs,
            type: :file,
            position: :last,
            variadic: true,
            min: 1
  end
end
```

**Usage examples:**

```ruby
# Modern double-dash equals
Inkscape.export(
  inputs: ["diagram.svg"],
  output: "diagram.pdf",
  format: :pdf,
  plain: true
)
# CLI: inkscape --export-filename=diagram.pdf --export-type pdf --export-plain-svg diagram.svg

# Using short options
Inkscape.export(
  inputs: ["diagram.svg"],
  output_short: "diagram.png",
  dpi: 300
)
# CLI: inkscape -o=diagram.png -d 300 diagram.svg

# Multiple input files
Inkscape.export(
  inputs: ["a.svg", "b.svg", "c.svg"],
  format: :png
)
# CLI: inkscape --export-type png a.svg b.svg c.svg
# Results in: a.png, b.png, c.png (same directory, same base name)
```

---

## Value Separators & Special Values

Many tools accept multiple values in a single option using separators:

### Separator Types

| Separator | Example | DSL | Use Case |
|-----------|---------|-----|----------|
| Comma | `--types=svg,png,pdf` | `separator: ","` | File types, extensions |
| Semicolon | `--ids=obj1;obj2;obj3` | `separator: ";"` | Object IDs, lists |
| Colon | `-r300x600` | `separator: "x"` | Dimensions (width×height) |
| Pipe | `--files=a\|b\|c` | `separator: "\|"` | Alternative paths |
| Space | `--search path1 path2` | `separator: " "` | Multiple paths |
| Plus | `--pages=1+3+5` | `separator: "+"` | Page numbers |

### Value Separator DSL

```ruby
command :process do
  # Comma-separated values
  option :formats,
          type: :array,
          of: :symbol,
          values: [:svg, :png, :pdf, :eps],
          cli: "--export-type=",
          separator: ","  # --export-type=svg,png,pdf

  # Semicolon-separated (Inkscape object IDs)
  option :objects,
          type: :array,
          of: :string,
          cli: "--export-id=",
          separator: ";"  # --export-id=obj1;obj2;obj3

  # Colon-separated (Ghostscript resolution)
  option :resolution,
          type: :array,
          of: :integer,
          size: 2,  # Exactly 2 values
          cli: "-r",
          separator: "x",  # -r300x600
          format: :single_dash_space

  # Space-separated paths (Ghostscript -I)
  option :lib_paths,
          type: :array,
          of: :file,
          cli: "-I",
          separator: " ",  # -I path1 path2 path3
          format: :single_dash_space
end
```

### Real-World Ghostscript Example

```ruby
class Ghostscript < Ukiryu::Wrapper
  tool "gs" do
    names "gs", "gswin64c", "gswin32c", "gsos2"
  end

  command :convert do
    # -sDEVICE=pdfwrite (string parameter, dash-s)
    option :device,
            type: :symbol,
            values: [:pdfwrite, :eps2write, :png16m, :jpeg],
            cli: "-sDEVICE=",
            format: :single_dash_equals

    # -r300 or -r300x600 (resolution, dash-r)
    option :resolution,
            type: :array,
            of: :integer,
            size: [1, 2],  # 1 or 2 values
            cli: "-r",
            format: :single_dash_space,
            separator: "x",
            value_position: :embedded  # -r300 (no space)

    # -sOutputFile=out.pdf (output, dash-s string)
    option :output,
            type: :file,
            cli: "-sOutputFile=",
            format: :single_dash_equals

    # -dSAFER (define name, dash-d)
    flag :safer,
          cli: "-dSAFER",
          format: :single_dash

    # -q (quiet, single letter flag)
    flag :quiet,
          cli: "-q"

    # -I path1 path2 path3 (search paths, variadic option)
    option :lib_paths,
            type: :array,
            of: :file,
            cli: "-I",
            format: :single_dash_space,
            separator: " ",
            repeatable: true  # Can use -I multiple times

    # Input file(s) at end
    argument :inputs,
            type: :file,
            position: :last,
            variadic: true,
            min: 1
  end
end
```

**Usage examples:**

```ruby
# Simple PDF conversion
Ghostscript.convert(
  inputs: ["input.ps"],
  output: "output.pdf",
  device: :pdfwrite,
  safer: true,
  quiet: true
)
# CLI: gs -sDEVICE=pdfwrite -sOutputFile=output.pdf -dSAFER -q input.ps

# With resolution (single value)
Ghostscript.convert(
  inputs: ["input.pdf"],
  output: "output.png",
  device: :png16m,
  resolution: [300]
)
# CLI: gs -sDEVICE=png16m -sOutputFile=output.png -r300 input.pdf

# With resolution (two values: X×Y)
Ghostscript.convert(
  inputs: ["input.pdf"],
  output: "output.png",
  device: :png16m,
  resolution: [300, 600]
)
# CLI: gs -sDEVICE=png16m -sOutputFile=output.png -r300x600 input.pdf

# With library paths
Ghostscript.convert(
  inputs: ["input.ps"],
  output: "output.pdf",
  lib_paths: ["/usr/local/share/ghostscript", "/custom/path"]
)
# CLI: gs -I /usr/local/share/ghostscript /custom/path -sDEVICE=pdfwrite ...
```

### Special Values

Some tools use special values with meaning:

```ruby
command :convert do
  # Ghostscript: -sOutputFile=- (stdout)
  option :output,
          type: :file,
          cli: "-sOutputFile=",
          special_values: {
            stdout: "-",        # -sOutputFile=-
            pipe: "%pipe%lpr",  # -sOutputFile=%pipe%lpr
            template: "%d"      # -sOutputFile=file%d.pdf
          }

  # Inkscape: --export-type=TYPE[,TYPE]* (multiple types)
  option :export_types,
          type: :array,
          of: :symbol,
          values: [:svg, :png, :ps, :eps, :pdf],
          cli: "--export-type=",
          separator: ","
end
```

---

## Environment Variables

Tools often require custom environment variables:

### Environment Variable DSL

```ruby
command :run do
  # Set environment variables for this command
  env_vars do
    set "MY_VAR", from: :option  # From user-provided option
    set "PATH", append: "/usr/local/bin"  # Append to existing
    set "DISPLAY", value: ""  # Set explicitly (headless mode)
    set "MAGICK_CONFIGURE_PATH", from: :option, default: "/etc/ImageMagick"
  end

  option :my_var,
          type: :string,
          desc: "Value for MY_VAR environment variable"

  option :config_path,
          type: :file,
          desc: "Path for MAGICK_CONFIGURE_PATH"
end
```

### Real-World Examples

**Inkscape headless operation:**

```ruby
class Inkscape < Ukiryu::Wrapper
  command :export do
    # Disable display on Unix/macOS for headless operation
    env_vars do
      set "DISPLAY", value: "", on: [:macos, :linux]
      # Windows: no DISPLAY variable needed
    end
  end
end
```

**ImageMagick with custom config:**

```ruby
class ImageMagick < Ukiryu::Wrapper
  command :convert do
    env_vars do
      set "MAGICK_CONFIGURE_PATH", from: :config_dir
      set "MAGICK_HOME", from: :install_dir
    end

    option :config_dir,
            type: :file,
            desc: "Custom configuration directory"

    option :install_dir,
            type: :file,
            desc: "ImageMagick installation directory"
  end
end
```

**Ghostscript with library path:**

```ruby
class Ghostscript < Ukiryu::Wrapper
  command :convert do
    env_vars do
      # GS_LIB is used to find initialization files and fonts
      set "GS_LIB", from: :lib_path
    end

    option :lib_path,
            type: :file,
            desc: "Ghostscript library path"
  end
end
```

### Shell-Specific Environment Variable Syntax

| Shell | Syntax | Example |
|-------|--------|---------|
| Bash/Zsh | `VAR=value` | `DISPLAY="" ./command` |
| PowerShell | `$ENV:VAR = "value"` | `$ENV:DISPLAY = ""; ./command` |
| Cmd | `set VAR=value` | `set DISPLAY= && command` |

Ukiryu handles the correct syntax for each shell automatically.

---

## Subcommands (Git-Style)

Many tools use subcommands with their own options:

### Subcommand DSL

```ruby
class Git < Ukiryu::Wrapper
  tool "git" do
    names "git"
  end

  # Subcommand: git add
  subcommand :add, desc: "Add files to staging" do
    argument :files,
            type: :file,
            variadic: true,
            min: 0  # Can add nothing (stage current changes)

    flag :all, cli: "--all"
    flag :update, cli: "--update"
    flag :verbose, cli: "-v"
  end

  # Subcommand: git commit
  subcommand :commit, desc: "Commit changes" do
    flag :all, cli: "--all", cli_short: "-a"
    flag :amend, cli: "--amend"
    flag :verbose, cli: "--verbose", cli_short: "-v"

    option :message,
            type: :string,
            cli: "-m",
            format: :single_dash_space,
            separator: " "

    flag :no_edit, cli: "--no-edit"
  end

  # Subcommand: git push
  subcommand :push, desc: "Push to remote" do
    argument :remote,
            type: :string,
            required: false,
            default: "origin"

    argument :branch,
            type: :string,
            required: false

    flag :force, cli: "--force", cli_short: "-f"
    flag :set_upstream, cli: "--set-upstream", cli_short: "-u"
    flag :verbose, cli: "--verbose", cli_short: "-v"
  end
end
```

### Subcommand Usage

```ruby
# git add file1.rb file2.rb
Git.add(files: ["file1.rb", "file2.rb"], all: false)
# CLI: git add file1.rb file2.rb

# git add -A
Git.add(files: [], all: true)
# CLI: git add --all

# git commit -m "Fix bug"
Git.commit(message: "Fix bug")
# CLI: git commit -m "Fix bug"

# git commit -am "Update"
Git.commit(all: true, message: "Update")
# CLI: git commit -a -m "Update"

# git push origin main
Git.push(remote: "origin", branch: "main")
# CLI: git push origin main

# git push (uses defaults)
Git.push
# CLI: git push
```

### Subcommand with Profiles

Different subcommands may have different profiles:

```ruby
tool "docker" do
  # docker build
  subcommand :build do
    profile :modern,
            platform: :any,
            shell: :any,
            version: ">= 20.0" do
      # Docker 20+ uses --build-arg
      option :build_args,
              type: :hash,
              cli: "--build-arg="
    end

    profile :legacy,
            platform: :any,
            shell: :any,
            version: "< 20.0" do
      # Docker < 20 used different syntax
      option :build_args,
              type: :hash,
              cli: "--build-arg"
    end
  end
end
```

---

## Shell-Specific Examples (cmd vs PowerShell)

### Windows cmd.exe

```ruby
tool "mytool" do
  profile :windows_cmd,
          platform: :windows,
          shell: :cmd do
    # cmd.exe uses: /option value
    option_style :slash_space

    # Special escaping for cmd (^ is escape char)
    escape_with :caret

    # Environment variables: %VAR%
    env_var_format :percent
  end
end
```

**cmd.exe escaping:**
```ruby
# In cmd: paths with spaces need quotes
MyTool.run(file: "C:\\Program Files\\input.txt")
# CLI: mytool /Input "C:\Program Files\input.txt"

# Special characters need caret escaping
MyTool.run(text: "hello & world")
# CLI: mytool /Input "hello ^& world"
```

### Windows PowerShell

```ruby
tool "mytool" do
  profile :windows_powershell,
          platform: :windows,
          shell: :powershell do
    # PowerShell can use: --option=value (Unix-style)
    option_style :double_dash_equals

    # Special escaping for PowerShell (` is escape char)
    escape_with :backtick

    # Environment variables: $ENV:VAR
    env_var_format :env_prefix
  end
end
```

**PowerShell escaping:**
```ruby
# In PowerShell: backtick escaping for special chars
MyTool.run(text: "hello `& world")
# CLI: mytool --input "hello `& world"

# Environment variables
env_vars do
  set "MY_VAR", from: :option
  # PowerShell: $ENV:MY_VAR = "value"
end
```

### Comparison Table

| Feature | Bash/Zsh | PowerShell | cmd.exe |
|---------|----------|------------|---------|
| Option style | `--flag=value` | `--flag=value` | `/flag value` |
| Quote | `'` | `'` | `"` |
| Escape char | `\` | `` ` `` | `^` |
| Env var | `$VAR` | `$ENV:VAR` | `%VAR%` |
| Path separator | `/` | `/` or `\` | `\` |
| Special chars escape | `\` & \| > < | `` ` `` $ " | `^` & \| < > |

### Example: Same Command, Different Shells

```ruby
class Converter < Ukiryu::Wrapper
  tool "convert" do
    names "convert"

    command :process do
      option :input,
              type: :file,
              cli: "--input="

      option :output,
              type: :file,
              cli: "--output="

      option :quality,
              type: :integer,
              cli: "--quality="

      flag :verbose, cli: "--verbose"

      argument :files,
              type: :file,
              variadic: true
    end
  end
end
```

**Bash (macOS/Linux):**
```ruby
Converter.process(
  input: "diagram.svg",
  output: "result.png",
  quality: 95,
  verbose: true,
  files: ["overlay.png"]
)
# CLI: convert --input='diagram.svg' --output='result.png' --quality=95 --verbose 'overlay.png'
```

**PowerShell:**
```ruby
Converter.process(
  input: "C:\\Files\\diagram.svg",
  output: "C:\\Files\\result.png",
  quality: 95,
  verbose: true,
  files: ["C:\\Files\\overlay.png"]
)
# CLI: convert --input='C:\Files\diagram.svg' --output='C:\Files\result.png' --quality=95 --verbose 'C:\Files\overlay.png'
```

**cmd.exe:**
```ruby
Converter.process(
  input: "C:\\Files\\diagram.svg",
  output: "C:\\Files\\result.png",
  quality: 95,
  verbose: true,
  files: ["C:\\Files\\overlay.png"]
)
# CLI: convert /Input "C:\Files\diagram.svg" /Output "C:\Files\result.png" /Quality 95 /Verbose "C:\Files\overlay.png"
```

---

## Command Declaration

```ruby
class MyToolWrapper < Ukiryu::Wrapper
  tool "mytool" do
    # ==================================================
    # COMMAND: export
    # ==================================================
    command :export, desc: "Export to different format" do

      # POSITIONAL argument (order matters!)
      argument :input,
              type: :file,
              position: 1,
              required: true

      # OPTION (named parameter with value)
      option :format,
              type: :symbol,
              values: [:pdf, :eps, :svg, :png],
              cli: "--format=",
              required: true

      # FLAG (boolean, presence indicates true)
      flag :plain,
            cli: "--plain",
            default: false

      # OUTPUT (where output goes)
      output :file,
            type: :file,
            via: :option,          # Uses --export-filename= option
            cli: "--export-filename=",
            position: :last
    end

    # ==================================================
    # COMMAND: query
    # ==================================================
    command :query, desc: "Query document properties" do

      argument :input,
              type: :file,
              required: true

      flag :width,
            cli: "--query-width"

      flag :height,
            cli: "--query-height"

      # Parse output into hash
      parse_output do |stdout|
        {
          width: stdout[/Width:\s*(\d+)/, 1].to_i,
          height: stdout[/Height:\s*(\d+)/, 1].to_i
        }
      end
    end
end
```

### Parameter/Option/Flag Distinctions

| Concept | DSL | Description | Example |
|---------|-----|-------------|--------|
| **Positional Argument** | `argument` | Position in command line, no `--flag` | `input.pdf` |
| **Variadic Argument** | `argument variadic: true` | Accepts multiple values (one or more) | `file1.pdf file2.pdf file3.pdf` |
| **Option** | `option` | Named parameter with value, has `--flag=` syntax | `--format=pdf` |
| **Flag** | `flag` | Boolean option (present/absent), no value | `--plain` |

### Variadic Arguments (Multiple Values)

Many CLI tools accept multiple values for a single argument position:

| Pattern | Example CLI | DSL |
|---------|-------------|-----|
| `command arg1 arg2*` | `cp file1 file2... dest` | `arg1` (pos 1), `arg2` (pos 2, variadic) |
| `command arg1* arg2` | `convert input... output` | `arg1` (pos 1, variadic), `arg2` (pos 2) |
| `command arg1 arg2* arg3` | `tar -cf archive files...` | `arg1`, `arg2*`, `arg3` with positions |
| `command arg1*` | `cat files...` | Single variadic argument |
| `command arg1 arg2*` (zero ok) | `git add [files...]` | `variadic: true, min: 0` |

#### DSL for Variadic Arguments

```ruby
command :export do
  # Single argument (standard)
  argument :input,
          type: :file,
          position: 1,
          required: true

  # Variadic: one or more files
  argument :sources,
          type: :file,
          position: 2,
          variadic: true  # Default: min: 1

  # Variadic: zero or more files (optional)
  argument :extras,
          type: :file,
          position: 3,
          variadic: true,
          min: 0

  # Required argument after variadic (must come after)
  argument :output,
          type: :file,
          position: :last,
          required: true
end
```

#### Usage Examples

```ruby
# Single variadic at end
# CLI: inkscape output.pdf input1.svg input2.svg input3.svg
Inkscape.export(
  output: "output.pdf",
  inputs: ["input1.svg", "input2.svg", "input3.svg"]
)

# Variadic in middle
# CLI: convert input1.jpg input2.jpg output.png
Convert.convert(
  sources: ["input1.jpg", "input2.jpg"],
  output: "output.png"
)

# Multiple variadic arguments
# CLI: tool required.txt optional1.txt optional2.txt final.txt
Tool.run(
  required: "required.txt",
  optional: ["optional1.txt", "optional2.txt"],  # Can be empty []
  final: "final.txt"
)

# Variadic with min: 0 (optional)
# CLI: git add [files...]
Git.add(
  files: ["file1.rb", "file2.rb"]
)
Git.add  # No files - valid when min: 0
```

#### Variadic Argument Rules

1. **Cardinality options:**
   - `variadic: true` - One or more values (default `min: 1`)
   - `variadic: true, min: 0` - Zero or more values (optional)
   - `variadic: true, min: 2` - At least N values (custom minimum)

2. **Position specification:**
   - Single variadic can use `position: N`
   - Multiple variadic arguments require explicit `position: N` for each
   - `position: :last` always comes after all other arguments

3. **Type validation:**
   - Each value in the array is validated individually
   - If any value fails validation, entire command fails before execution

4. **Command building:**
   - Variadic arguments expand to N CLI arguments in order
   - `inputs: ["a.svg", "b.svg"]` → `a.svg b.svg` in command line

#### Real-World Examples

**Copy command (cp):**
```ruby
class Cp < Ukiryu::Wrapper
  tool "cp" do
    names "cp"
  end

  command :copy do
    # cp source... destination
    argument :sources,
            type: :file,
            position: 1,
            variadic: true,
            min: 1  # At least one source

    argument :destination,
            type: :file,
            position: :last,
            required: true
  end
end

# Usage:
Cp.copy(sources: ["file1.txt", "file2.txt"], destination: "dest/")
# CLI: cp file1.txt file2.txt dest/
```

**ImageMagick convert (inputs before output):**
```ruby
class ImageMagick < Ukiryu::Wrapper
  tool "convert" do
    names "convert", "magick"
  end

  command :convert do
    # convert input... [options] output
    argument :inputs,
            type: :file,
            position: 1,
            variadic: true,
            min: 1

    option :resize,
            type: :string,
            cli: "-resize "

    argument :output,
            type: :file,
            position: :last,
            required: true
  end
end

# Usage:
ImageMagick.convert(
  inputs: ["a.jpg", "b.jpg", "c.jpg"],
  resize: "50%",
  output: "combined.png"
)
# CLI: convert a.jpg b.jpg c.jpg -resize 50% combined.png
```

**Git add (zero or more files):**
```ruby
class Git < Ukiryu::Wrapper
  tool "git" do
    names "git"
  end

  command :add do
    argument :files,
            type: :file,
            position: 1,
            variadic: true,
            min: 0  # Optional: can add nothing to stage current changes
    flag :all, cli: "--all"
    flag :update, cli: "--update"
  end
end

# Usage:
Git.add(files: ["file1.rb", "file2.rb"])
# CLI: git add file1.rb file2.rb

Git.add  # No files, but valid
# CLI: git add
```

### Type System

All types with validation and escaping:

| Type | Description | Validation | Escaped | Example |
|------|-------------|------------|---------|---------|
| `:file` | File path | Must exist, platform-validated | Shell-specific | `file.pdf` |
| `:string` | Text string | Custom validation | Shell-specific | `"hello"` |
| `:integer` | Whole number | Range check | No escaping | `95` |
| `:float` | Decimal | Custom validation | No escaping | `1.5` |
| `:symbol` | Enum value | Must be in whitelist | No escaping | `:pdf` |
| `:boolean` | Boolean flag | N/A | Flag presence | `--verbose` |
| `:uri` | URL/URI | Must be valid URI | Shell-specific | `https://example.com` |
| `:datetime` | Date/time | Must be parseable | Formatted, then escaped | `2025-01-21` |
| `:hash` | Key-value pairs | Recursively escaped | Merge into env vars | `{key: "value"}` |
| `:array` | Multiple values | Separator-based | Multiple arguments | `["a", "b"]` |

---

## Shell Classes

### Base Interface

```ruby
module Ukiryu
  module Shell
    class Base
      # Identify the shell
      def name => Symbol

      # Escape a string for this shell
      def escape(string) => String

      # Quote an argument
      def quote(string) => String

      # Format a file path
      def format_path(path) => String

      # Format environment variable reference
      def env_var(name) => String

      # Join executable and arguments
      def join(executable, *args) => String
    end
  end
end
```

### Bash Implementation

```ruby
module Ukiryu
  module Shell
    class Bash < Base
      def name; :bash; end

      def escape(string)
        # Single-quote string (literal)
        string.gsub("'") { "'\\''" }
      end

      def quote(string)
        "'#{escape(string)}'"
      end

      def format_path(path)
        path  # Unix paths are fine
      end

      def env_var(name)
        "$#{name}"
      end

      def join(executable, *args)
        [executable, *args.map { |a| quote(a) }].join(" ")
      end
    end
  end
end
```

### PowerShell Implementation

```ruby
module Ukiryu
  module Shell
    class PowerShell < Base
      def name; :powershell; end

      def escape(string)
        # Backtick escaping for: ` $ "
        string.gsub(/[`"$]/) { "`$0" }
      end

      def quote(string)
        "'#{escape(string)}'"
      end

      def format_path(path)
        path  # PowerShell handles forward slashes fine
      end

      def env_var(name)
        "$ENV:#{name}"
      end

      def join(executable, *args)
        [executable, *args.map { |a| quote(a) }].join(" ")
      end
    end
  end
end
```

### Cmd Implementation

```ruby
module Ukiryu
  module Shell
    class Cmd < Base
      def name; :cmd; end

      def escape(string)
        # Caret is escape character
        string.gsub(/[%^<>&|]/, '^^0')
      end

      def quote(string)
        if string =~ /[ \t]/
          "\"#{escape(string)}\""
        else
          escape(string)
        end
      end

      def format_path(path)
        # Convert to backslashes
        path.gsub('/', '\\')
      end

      def env_var(name)
        "%#{name}%"
      end

      def join(executable, *args)
        [executable, *args.map { |a| quote(a) }].join(" ")
      end
    end
  end
end
```

---

## Implementation Phases

### Phase 1: Foundation (6-8 weeks)
- Core gem structure
- Platform detection
- Shell detection (EXPLICIT)
- Basic type system (file, string, integer, symbol, boolean)
- Basic command execution
- Bash shell implementation

### Phase 2: Additional Types (3-4 weeks)
- Float, URI, datetime, hash types
- Array type with separators
- Path validation (platform-specific)

### Phase 3: More Shells (3-4 weeks)
- PowerShell shell implementation
- Cmd shell implementation
- Zsh fish implementation

### Phase 4: Profile System (4-6 weeks)
- Profile DSL
- Exact matching algorithm
- Version compatibility
- Profile error messages

### Phase 5: Complete DSL (4-6 weeks)
- Argument/option/flag distinction
- Position specification
- Output specification
- Conditional flags
- Option mapping

### Phase 6: Testing & Docs (6-8 weeks)
- GHA test matrix (platform × shell × ruby)
- Shell-specific documentation
- Platform-specific documentation
- Example wrappers

### Phase 7: Vectory Migration (4-6 weeks)
- Replace InkscapeWrapper
- Replace GhostscriptWrapper
- Full testing on all platforms

---

## Success Criteria

Ukiryu succeeds when:

1. ✅ **Explicit shell detection** - Raises clear error if shell unknown
2. ✅ **Exact profile matching** - No fallbacks (version compatibility OK)
3. ✅ **Type-safe parameters** - All types validated, shell-escaped automatically
4. ✅ **Semantic validation** - Platform-specific paths rejected on wrong platforms
5. ✅ **YAML profile register** - Tool definitions maintained in YAML, not code
6. ✅ **Schema validation** - All YAML profiles validated against JSON Schema
7. ✅ **Profile inheritance** - Avoid duplication with YAML inheritance
8. ✅ **Vectory replacement** - Full replacement of Vectory wrappers in 70% less code
9. ✅ **GHA testing** - All platform×shell combinations tested
10. ✅ **Complete documentation** - Separate docs for each shell/platform
11. ✅ **Zero dependencies** - Ruby stdlib only
12. ✅ **Argument/option/flag distinction** - Clear DSL concepts
13. ✅ **PATH-only on Unix** - No hardcoded paths on Unix/macOS
14. ✅ **Community register** - Separate register repo for tool profiles
15. ✅ **Option format variations** - Support all CLI option formats
16. ✅ **Value separators** - Comma, semicolon, colon, space, pipe, plus
17. ✅ **Environment variables** - Per-command environment variable support
18. ✅ **Subcommands** - Git-style subcommand support
19. ✅ **Shell-specific examples** - cmd.exe vs PowerShell examples

---

## Key Insights

1. **YAML profiles over Ruby DSL**: Tool definitions should be maintained in YAML files, not Ruby code. This allows:
   - Non-developers to add/update tools
   - Faster iteration without gem releases
   - Community-contributed profile register
   - Separation of framework (Ruby) from configuration (YAML)

2. **Hybrid architecture**:
   - **Ruby framework**: Shell detection, escaping, execution, validation
   - **YAML register**: Tool definitions, versions, platform profiles
   - Users can still use Ruby DSL for custom tools not in register

3. **"symbols in shell"**: User correctly pointed out that `:symbol` is a Ruby type, not a shell concept. In the shell, we pass strings. The `:symbol` type is for Ruby-level validation only.

4. **PATH environment**: On Unix, tools should be in PATH. No need to hardcode `/usr/bin`. Ukiryu should:
   - Always search `ENV["PATH"]` first
   - Add platform-specific paths only for platforms that need them (Windows app bundles, etc.)

5. **Option format variations**: CLI tools use many different formats:
   - `--flag=value` (double-dash equals)
   - `--flag value` (double-dash space)
   - `-f=value` (single-dash equals)
   - `-f value` (single-dash space)
   - `/flag value` (Windows slash)
   - `-r300` (embedded value)

6. **Value separators**: Many tools accept multiple values:
   - Comma: `--types=svg,png,pdf`
   - Semicolon: `--ids=obj1;obj2;obj3`
   - Colon: `-r300x600` (dimensions)
   - Space: `-I path1 path2`
   - Pipe, plus: for special cases

7. **Environment variables**: Per-command environment variables:
   - Inkscape: `DISPLAY=""` for headless on Unix
   - Ghostscript: `GS_LIB` for library path
   - ImageMagick: `MAGICK_CONFIGURE_PATH`

8. **Subcommands**: Git-style command structure:
   - `git add`, `git commit`, `git push`
   - Each subcommand has its own options
   - Shared options can be inherited

9. **Shell differences**:
   - **Bash/Zsh**: Single-quote escaping, `$VAR`, `/` paths
   - **PowerShell**: Backtick escaping, `$ENV:VAR`, `/` or `\` paths
   - **cmd.exe**: Caret escaping, `%VAR%`, `\` paths

10. **Explicit > Implicit**: Ukiryu must detect shell and profile explicitly, never guess.

11. **Type safety**: Users shouldn't deal with escaping at all—that's Ukiryu's job.

12. **Vectory as reference**: Vectory will be the first implementation driving Ukiryu development.

---

## Register Organization

**Register repo structure:**

```
ukiryu-register/                    # Community register repo
├── tools/                         # Tool definitions (dir by command name)
│   ├── inkscape/
│   │   ├── 1.0.yaml              # Version-specific profiles
│   │   ├── 0.92.yaml
│   │   └── 0.9.yaml
│   ├── ghostscript/
│   │   ├── 10.0.yaml
│   │   ├── 9.5.yaml
│   │   └── 9.0.yaml
│   ├── imagemagick/
│   │   ├── 7.0.yaml
│   │   └── 6.0.yaml
│   ├── git/
│   │   ├── 2.45.yaml
│   │   └── 2.40.yaml
│   ├── docker/
│   │   ├── 25.0.yaml
│   │   └── 24.0.yaml
│   └── ...
├── schemas/                       # YAML Schema files
│   ├── tool-profile.yaml.schema
│   ├── command-definition.yaml.schema
│   └── register.yaml.schema
├── docs/                          # AsciiDoc documentation
│   ├── inkscape.adoc
│   ├── ghostscript.adoc
│   ├── imagemagick.adoc
│   ├── git.adoc
│   ├── contributing.adoc
│   ├── register.adoc
│   └── README.adoc
├── lib/                           # Register helper library
│   └── ukiryu/
│       └── register.rb
├── Gemfile                         # json-schema gem
├── Rakefile                        # Validation tasks
└── README.adoc                     # Register overview
```

**Ukiryu gem structure:**

```
ukiryu/                             # Ruby gem
├── lib/
│   ├── ukiryu.rb
│   ├── ukiryu/
│   │   ├── register.rb            # YAML loader from register
│   │   ├── tool.rb                # Tool from YAML
│   │   ├── shell.rb               # Shell detection (EXPLICIT)
│   │   ├── shell/
│   │   │   ├── bash.rb
│   │   │   ├── zsh.rb
│   │   │   ├── powershell.rb
│   │   │   └── cmd.rb
│   │   ├── type.rb                # Type validation
│   │   ├── executor.rb            # Command execution
│   │   ├── version.rb             # Version detection
│   │   └── schema_validator.rb    # JSON::Schema wrapper
│   └── ukiryu.yml                  # Bundled profiles (optional)
├── spec/
│   └── ...
├── Gemfile                         # json-schema dependency
├── Rakefile
└── README.adoc
```

**Gemfile:**

```ruby
# ukiryu-register/Gemfile
source 'https://rubygems.org'

gem 'json-schema', '~> 3.0'
gem 'yaml', '~> 0.3'  # For schema validation
```

**Register README.adoc structure:**

```asciidoc
= Ukiryu Tool Register

== Overview

The Ukiryu Tool Register maintains YAML profiles for command-line tools.

== Tools

* link:tools/inkscape/[Inkscape]
* link:tools/ghostscript/[Ghostscript]
* link:tools/imagemagick/[ImageMagick]

== Contributing

See link:contributing.adoc[Contributing Guidelines].

== Validation

Run `rake validate` to validate all tool profiles.
```

---

## File Location

```
docs/ukiryu-proposal.md
```
