# Plan: AI-Native IDE Based on LiteXL ("LiteXL-AI")

## Vision
Transform LiteXL into a lightweight, AI-native IDE that directly competes with Cursor. Instead of forking heavyweight VS Code, we will build on LiteXL’s minimal, fast C/Lua core to create a performant, extensible AI-driven editor with repo-aware chat, agentic automation, and advanced autocomplete.

## Core Objectives
1. **AI-First Workflow**: Deeply integrate LLMs into editing, refactoring, and project-wide reasoning.
2. **Repo-Aware Context**: Enable AI to operate across the whole codebase, not just the current file.
3. **Agent System**: Implement an agent loop that can plan, execute, and review multi-file changes.
4. **Extensibility**: Preserve LiteXL’s plugin system and add AI-specific extension points.
5. **Performance**: Maintain LiteXL’s lightweight footprint while adding AI features.

## High-Level Architecture
- **AI Core Layer**: New Lua/C module for AI communication (HTTP/HTTPS to LLM APIs), context management, and agent orchestration.
- **UI Layer**: Add AI sidebar (chat), inline suggestion UI, and agent status widgets.
- **Context Engine**: Project indexing, symbol extraction, and context assembly for AI prompts.
- **Agent Loop**: Task planning, tool use (file edit, read, search, run commands), and human-in-the-loop review.
- **Plugin Integration**: Expose AI capabilities to plugins and allow plugins to contribute tools and context.

## Phase 1: Foundations (Basic AI Functionality)

### 1.1 AI Communication Module
- **File**: `data/core/ai.lua` (new)
- **Purpose**: HTTP client for LLM API calls (OpenAI, Anthropic, local models).
- **Functions**:
  - `ai.chat(messages, options)`: Send chat messages, return response.
  - `ai.completion(prompt, options)`: Inline/code completion.
  - `ai.stream(messages, callback)`: Streaming responses.
- **Configuration**: API keys, model selection, endpoint URLs in `config.plugins.ai`.
- **Dependencies**: Use Lua `socket` or wrap C HTTP (e.g., libcurl via native plugin).

### 1.2 AI Chat Sidebar
- **File**: `data/plugins/ai_chat.lua` (new plugin)
- **UI**: New `AiChatView` extending `core.view.View` for chat interface.
- **Features**:
  - Chat history (per project).
  - Message input (multiline) with send button.
  - Streaming response display.
  - Context selector (selected files, whole project).
  - Command palette integration (`ai:chat`).
  - Keybinding: `ctrl+shift+a` (configurable).
- **Integration**:
  - Uses `ai.chat` via the AI module.
  - Uses `context.get` to include project context.
  - Keybinding: `ctrl+shift+a` (configurable).

### 1.3 Basic Agent Loop
- **File**: `data/core/agent.lua` (new)
- **Purpose**: Simple agent that can perform multi-file edits via chat.
- **Workflow**:
  1. User selects files and enters a high-level request (e.g., “Add user registration”).
  2. Agent uses `context.get` to gather info.
  3. Agent calls `ai.chat` with a system prompt to generate a plan (list of steps).
  4. Agent presents plan for approval.
  5. On approval, agent executes steps (file read/edit, search) using new tools.
  6. Agent shows diff preview and applies changes.
- **Tools**:
  - `agent.read_file(path)`: Read file content.
  - `agent.edit_file(path, changes)`: Apply edits (diff).
  - `agent.search(query)`: Search project.
  - `agent.run_command(cmd)`: Execute shell command (optional, with Yolo mode).
- **UI**: `AgentView` sidebar to show plans, progress, and results.

### 1.4 Tool System
- **File**: `data/core/tools.lua` (new)
- **Purpose**: Registry and execution of tools for agents and AI.
- **Features**:
  - Tool registration (`tools.register(name, fn)`).
  - Built-in tools: read, edit, search, run.
  - Extensible: plugins can add tools.
  - Permission model: user approval for dangerous operations.
- **Integration**: Used by `agent.lua` and AI modules.

## Phase 2: Enhanced AI Features

### 2.1 Agent Mode ("Composer")
- **File**: Extend `data/core/agent.lua`
- **Features**:
  - Interactive planning UI with clarifying questions.
  - Multi-step tool use with loops and conditionals.
  - Human-in-the-loop checkpoints.
  - Plan saving/loading.
- **UI**: Enhance `AgentView` with plan tree, step status, and approval buttons.

### 2.2 AI Code Review
- **File**: `data/plugins/ai_review.lua` (new)
- **Purpose**: AI-driven code review for changes (git diffs).
- **Workflow**:
  - Hook into git to get staged changes.
  - Send diff to AI with review prompt.
  - Show review comments inline or in sidebar.
  - Allow applying AI-suggested fixes.
- **Integration**: Use `ai.chat` and `context.get`.

### 2.3 Terminal Awareness & Yolo Mode
- **File**: Extend `data/core/agent.lua`
- **Features**:
  - Capture terminal output and errors.
  - Auto-suggest fixes based on errors.
  - Yolo mode: auto-run commands to fix issues (configurable).
- **UI**: Show terminal-aware suggestions in `AgentView`.

### 2.4 Multi-Model Support
- **File**: Extend `data/core/ai.lua`
- **Features**:
  - Configure different models for chat, completion, and agent tasks.
  - Support local models via Ollama or LM Studio.
  - Model routing based on task type and cost.
- **Configuration**: Per-model settings in `config.plugins.ai`.

### 2.5 Memory & Rules
- **File**: `data/core/memory.lua` (new)
- **Purpose**: Persistent memory for project-specific instructions and rules.
- **Features**:
  - Store/retrieve key-value facts (e.g., “use PostgreSQL for prod”).
  - Rules engine for enforcing conventions (e.g., “no console.log in prod”).
  - AI can query memory during tasks.
- **Storage**: JSON file in project directory (`.lite-xl-ai/memory.json`).

## Phase 3: Ecosystem & Advanced Features

### 3.1 MCP (Model Context Protocol) Server Support
- **File**: `data/core/mcp.lua` (new)
- **Purpose**: Connect external tools via MCP.
- **Features**:
  - Discover and connect MCP servers.
  - Expose tools to agent.
  - Context sharing.
- **Integration**: Extend `agent.lua` tools.

### 3.2 Multi-Agent System
- **File**: `data/core/multi_agent.lua` (new)
- **Purpose**: Orchestrate multiple specialized agents (e.g., “frontend”, “backend”, “testing”).
- **Features**:
  - Agent registry and routing.
  - Inter-agent communication.
  - Collaborative task execution.
- **UI**: Agent status dashboard.

### 3.3 Advanced Autocomplete
- **File**: Extend `data/plugins/autocomplete.lua`
- **Features**:
  - Repo-aware completions using context engine.
  - Fine-tuned local model support.
  - Template-based completions (e.g., for boilerplate).
  - Performance: Cache and debounce requests.
- **Integration**: Use `ai.completion` and `context.get`.

## Implementation Notes

### Integration Points
- **Event System**: Use LiteXL’s event system for context invalidation and agent updates.
- **Plugin API**: Expose AI functions via plugin API for third-party extensions.
- **Configuration**: Extend `config` system for AI settings.
- **Theming**: Add AI-specific colors and icons.

### Performance Considerations
- **Async Operations**: Use Lua coroutines for non-blocking AI requests.
- **Caching**: Aggressively cache context and AI responses.
- **Resource Limits**: Configurable limits on context size and API usage.

### Security
- **API Keys**: Store securely (environment variables or encrypted config).
- **Sensitive Data**: Blocklist or redact sensitive files from context.
- **Yolo Mode**: Require explicit consent for auto-run commands.

### Testing
- **Unit Tests**: For AI module, context engine, and agent tools.
- **Integration Tests**: Mock LLM API responses for reproducible tests.
- **Manual Tests**: Sample projects for agent workflows.

## File Structure (New/Modified Files)
```
data/core/
  ai.lua              -- AI communication module
  context.lua         -- Context engine
  agent.lua           -- Agent loop and tools
  tools.lua           -- Tool registry and execution
  memory.lua          -- Memory and rules
  mcp.lua             -- MCP server support
  multi_agent.lua     -- Multi-agent orchestration
  team.lua            -- Team features
data/plugins/
  ai_chat.lua         -- AI chat sidebar
  ai_review.lua       -- AI code review
  autocomplete.lua    -- Extended with AI completions
resources/
  icons/              -- AI-specific icons
docs/
  ai.md               -- AI feature documentation
```

## Milestones
- **M1 (Phase 1)**: Basic AI chat, inline completions, simple agent loop, tool system (2–3 weeks).
- **M2 (Phase 2)**: Enhanced agent, code review, terminal awareness, multi-model support, memory/rules (3–4 weeks).
- **M3 (Phase 3)**: MCP, multi-agent, team features, remote development, advanced autocomplete (4–6 weeks).

## Risks and Mitigations
- **API Latency**: Use streaming and caching; support local models.
- **Context Overload**: Implement smart context truncation and summarization.
- **User Adoption**: Preserve LiteXL’s core UX; make AI features opt-in initially.
- **Cost**: Allow model selection and usage caps.

## Conclusion
By building on LiteXL’s lightweight, extensible architecture, we can create a performant, AI-native IDE that rivals Cursor without the overhead of VS Code. This plan provides a clear roadmap from foundational AI features to advanced agentic capabilities.