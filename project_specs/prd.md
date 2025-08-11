# Elixir Gemini CLI Replication Product Requirements Document (PRD)

## Goals and Background Context

### Goals

- Successfully port all key features from the `google-gemini/gemini-cli` source project to a new Elixir codebase.
    
- Create a system that is demonstrably more robust, scalable, and maintainable than the original project.
    
- Achieve true model-agnosticism by building a flexible abstraction layer that supports multiple LLM providers.
    

### Background Context

The reference `gemini-cli` project is a sophisticated AI agent built on Node.js/TypeScript. While functional, its architecture lacks the intrinsic fault tolerance, state management, and supervision capabilities that are native to Elixir's OTP. This project is an opportunity for significant architectural improvement, building a more resilient and powerful system from the ground up by leveraging a superior paradigm for this specific application.

### Change Log

|   |   |   |   |
|---|---|---|---|
|**Date**|**Version**|**Description**|**Author**|
|August 11, 2025|1.0|Initial PRD Draft|John (PM)|

## Requirements

### Functional Requirements

1. The agent's core logic must be implemented as a "Reason and Act" (ReAct) loop to form a plan, use tools, and observe results until the user's goal is achieved.
    
2. The system must support multi-modal inputs, allowing users to submit content like PDFs and images for processing.
    
3. A built-in tool for grounding responses with Google Search must be provided.
    
4. A built-in tool for reading from and writing to the local filesystem must be provided. All file access must be sandboxed and validated against a list of allowed directories.
    
5. A built-in tool for executing shell commands must be available. This tool's sandboxing feature must be **enabled by default** but allow for bypass via a configuration setting.
    
6. The system must load context from hierarchical `GEMINI.md` files by searching upwards from the current directory.
    
7. Users must be able to checkpoint (save) and restore conversation sessions.
    
8. The system must support a flexible, multi-layered authentication and authorization strategy:
    
    - **User Authentication**:
        
        - **Web UI**: The system must support user login via a standard browser-based Google Account OAuth flow.
            
        - **TUI/CLI**: For terminal-based interfaces, the system must initiate a device authorization flow, printing a clickable URL that allows the user to authenticate in a browser and grant permission to the application.
            
    - **Backend to LLM Authentication**: The core agent must be able to authenticate with various LLM providers using multiple methods, including direct API Keys and user-delegated OAuth tokens.
        
    - **Enterprise Authentication**: The system must support Google Cloud service accounts via Vertex AI for enterprise use cases.
        
9. The primary user interface must be a real-time web application that can render streaming text output and display the agent's current status (e.g., thinking, using a tool).
    
10. The application must provide a configuration mechanism to manage security settings, including enabling or bypassing the shell tool sandbox.
    
11. The agent must have a tool that can interpret an OpenAPI specification to make API calls, enabling it to interact with other services programmatically.
    

### Non-Functional Requirements

1. The architecture must enforce a strict separation of concerns, with the core agentic logic completely decoupled from the user interface.
    
2. Each user session must be managed by an isolated, supervised OTP `GenServer` process to ensure fault tolerance. All long-running processes must be part of a supervision tree.
    
3. The system must be model-agnostic, achieved by defining an `LLMProvider` behaviour that abstracts the specific details of different LLM providers.
    
4. The system must be extensible, achieved by defining a `Tool` behaviour that allows new tools to be added in a standardized way.
    
5. The codebase must adhere to community standards by enforcing universal code formatting via `mix format` and static analysis via `Credo` in a CI/CD pipeline.
    
6. All public modules and functions must be documented using `@moduledoc`/`@doc` and include typespecs via `@spec`. Documentation examples for pure functions must be testable using doctests.
    
7. The application structure must follow the Phoenix Context pattern, grouping related functionality into cohesive domain modules. Contexts must not call each other directly.
    
8. The system must use a standard monolithic ("poncho") structure as the default, avoiding the complexity of Umbrella projects unless a specific, near-term need for separate deployment is proven.
    
9. The primary web interface will be built using Phoenix LiveView to handle real-time, stateful interactions efficiently over a persistent WebSocket connection.
    
10. **Epic Demonstrations**: Each completed epic must produce a runnable, self-contained demo located in the `demos/[epic_name]/` directory. The demo must include a `README.md` guide explaining its purpose and how to run it.
    
11. **Iterative Tutorials**: Each completed story must produce a corresponding educational tutorial in Markdown format. The tutorial should teach an intermediate Elixir developer how the story's features were built, styled like a blog post with code snippets and explanations. Tutorials must be located in `tutorials/[epic_name]/[story_name]/`, and a main `tutorials/index.md` file must be updated with a link to the new tutorial.
    

## User Interface Design Goals

### Overall UX Vision

The user experience should provide a transparent, real-time window into the agent's reasoning process. The primary goal is to create a fluid, conversational interface that empowers developers by giving them a clear view of the agent's thoughts, the tools it uses, and the results it produces. The interface should feel like a power-user tool: efficient, clear, and controllable.

### Key Interaction Paradigms

- **Conversational Chat**: The core interaction will be a chat-style interface for sending prompts and receiving responses.
    
- **Real-time Streaming**: Text responses from the agent will stream into the UI in real-time to provide immediate feedback.
    
- **Structured Tool Display**: When the agent uses a tool, the UI will display this action in a structured, easy-to-read format, showing the tool called, its parameters, and the result.
    
- **Session Control**: Users will have clear controls to stop a generating response, save the current session state, and restore previous sessions.
    

### Core Screens and Views

- **Main Agent Interface**: The primary screen containing the chat history, prompt input, and real-time status indicators.
    
- **Session Management**: A view to list, load, and manage saved conversation checkpoints.
    
- **Settings / Configuration**: A screen for users to manage API keys, authentication methods, and behavior settings (like the shell sandbox bypass).
    
- **Authentication**: A simple page to handle the redirect-based Google OAuth flow.
    

### Accessibility: WCAG AA

- **(Assumption)** The application will adhere to Web Content Accessibility Guidelines (WCAG) 2.1 Level AA standards to ensure it is usable by developers with diverse abilities.
    

### Branding

- **(Assumption)** The visual aesthetic will be clean, minimalist, and developer-focused, similar to modern IDEs or technical documentation sites. It will prioritize typography and clarity, with a professional color palette and a high-quality dark mode.
    

### Target Device and Platforms: Web Responsive

- The primary interface will be a responsive web application, designed to work flawlessly on modern desktop browsers where developer work is typically done.
    

## Technical Assumptions

### Repository Structure: Monorepo (Standard "Poncho" Application)

The project will be structured as a standard monolithic application, often called a "poncho" app in the Elixir community.

- **Rationale**: This is the recommended default for the vast majority of Elixir projects, especially single, deployable applications like this one. It provides the best tooling support from the ecosystem and avoids the significant developer overhead and complexity associated with Umbrella projects. Logical separation of concerns will be enforced through disciplined use of Phoenix Contexts rather than compile-time boundaries.
    

### Service Architecture

The architecture will consist of a core agentic engine built on OTP principles, completely decoupled from any user interface.

- **Core Logic**: The application's core business logic will be organized into **Phoenix Contexts**, which serve as the public API for a discrete part of the application's domain. Contexts will be kept decoupled by using a higher-level **Service Layer** to orchestrate any cross-context operations.
    
- **State Management**: Each user's conversation will be managed in an isolated, stateful, and supervised **GenServer** process.
    
- **Extensibility**: The system will be made model-agnostic and extensible through the use of Elixir **behaviours**, which act as formal contracts (interfaces) for different LLM providers and Tools.
    

### Testing Requirements

The project will employ a full testing pyramid strategy.

- **Rationale**: To ensure a robust and maintainable application, a comprehensive testing approach is required. This includes unit tests, integration tests, and end-to-end tests.
    
- **Testable Documentation**: A key practice will be the use of **doctests** for all pure functions. This makes documentation examples executable as part of the test suite, guaranteeing that documentation is always synchronized with the code.
    

### Additional Technical Assumptions and Requests

- **Primary Technology Stack**: The application will be built with Elixir and the Phoenix web framework.
    
- **Primary User Interface**: The primary web UI will be built using **Phoenix LiveView** to provide a rich, real-time user experience with server-rendered HTML.
    
- **Code Quality Enforcement**: The project will programmatically enforce code quality. All code must be formatted with `mix format` and must pass static analysis checks from `Credo`, integrated into a CI pipeline.
    
- **Documentation Standard**: All public modules and functions must be documented (`@moduledoc`/`@doc`) and include type specifications (`@spec`).
    

## Epic List

1. **Epic 1: Foundation & Core Agent Engine**
    
    - **Goal**: Establish the foundational OTP application, the core ReAct agent logic, a single LLM provider connection, and the metaprogramming DSL for tools, creating a testable backend engine.
        
2. **Epic 2: Phoenix LiveView UI & User Authentication**
    
    - **Goal**: Implement the real-time web interface using Phoenix LiveView and enable secure user login via the web and CLI OAuth flows, allowing users to interact directly with the core agent.
        
3. **Epic 3: Advanced Agent Capabilities & Tooling**
    
    - **Goal**: Expand the agent's power by adding multi-provider LLM support (OpenAI, Anthropic), implementing the full suite of sandboxed tools (File I/O, Shell, OpenAPI), and enabling session checkpointing/restoration.
        
4. **Epic 4: Terminal User Interface (TUI)**
    
    - **Goal**: Create a terminal-based interface as an alternative "head" for interacting with the completed core agent, providing a feature-complete CLI experience.
        

## Epic 1: Foundation & Core Agent Engine

This epic's purpose is to construct the skeleton of our application and implement the absolute core of the AI agent. By the end of this epic, we will have a functional, testable backend engine that can hold a conversation, connect to an LLM, and use a basic, secure tool. This lays the groundwork for all future user-facing features.

### Story 1.1: Integrate Code Quality Tooling

- **As a** Developer,
    
- **I want** to integrate and configure standard code quality tools into the existing project,
    
- **so that** all development adheres to community best practices.
    

**Acceptance Criteria**

1. `mix format` is configured via `.formatter.exs` to check all `lib`, `test`, and `config` directories.
    
2. `Credo` is added as a dev/test dependency and configured with a default `.credo.exs`.
    
3. A CI/CD workflow file (e.g., for GitHub Actions) is created that runs `mix format --check-formatted` and `mix credo --strict`.
    
4. The `README.md` is updated with basic project information and setup instructions.
    
5. The project successfully compiles with the new dependencies.
    
6. A tutorial for this story is created in `tutorials/epic1/story1.1/`, and the main `tutorials/index.md` is updated with a link to it.
    

### Story 1.2: Core Application & Supervision Tree

- **As a** Developer,
    
- **I want** a basic OTP application with a dynamic supervisor,
    
- **so that** agent processes can be started and managed with fault tolerance.
    

**Acceptance Criteria**

1. An `Application` module is defined and added to the supervision tree.
    
2. A `DynamicSupervisor` is successfully started and supervised by the main application supervisor.
    
3. A placeholder `Agent` GenServer module is created.
    
4. The `DynamicSupervisor` can successfully start, supervise, and restart a child `Agent` process.
    
5. A tutorial for this story, explaining the OTP structure, is created in `tutorials/epic1/story1.2/` and the main `tutorials/index.md` is updated.
    

### Story 1.3: Agent State Management & ReAct Loop Stub

- **As an** Agent,
    
- **I want** to manage a conversation's state within a GenServer and have a basic ReAct loop structure,
    
- **so that** I can maintain context and begin processing prompts.
    

**Acceptance Criteria**

1. The `Agent` GenServer's state is defined in a struct, including `message_history` and `loop_state`.
    
2. A public API function exists to send a user prompt to the `Agent` process.
    
3. The `Agent` GenServer implements a placeholder ReAct loop that receives a prompt, updates the `message_history`, and returns a hardcoded response without calling an LLM.
    
4. The agent's state is correctly updated after processing a prompt.
    
5. A tutorial for this story, explaining GenServer state and message handling, is created in `tutorials/epic1/story1.3/` and the main `tutorials/index.md` is updated.
    

### Story 1.4: LLMProvider Behaviour & Gemini Adapter

- **As a** Developer,
    
- **I want** a model-agnostic `LLMProvider` behaviour and a concrete Gemini adapter,
    
- **so that** the agent can communicate with the Gemini LLM.
    

**Acceptance Criteria**

1. An `LLMProvider` behaviour is defined with callbacks for text completions and tool-use completions.
    
2. The `gemini_ex` library is added as a dependency.
    
3. A `MyApp.Providers.Gemini` module is created that implements the `LLMProvider` behaviour.
    
4. The Gemini adapter is configured with an API key via application environment variables.
    
5. The `Agent` GenServer is updated to use the `LLMProvider` behaviour, which is configurable at runtime.
    
6. Given a valid API key, the agent can successfully get a simple text response from the Gemini API and add it to its state.
    
7. A tutorial for this story, explaining the behaviour-based adapter pattern, is created in `tutorials/epic1/story1.4/` and the main `tutorials/index.md` is updated.
    

### Story 1.5: Tooling DSL & Sandboxed File Tool

- **As a** Developer,
    
- **I want** a metaprogramming DSL for defining tools and an initial sandboxed file-reading tool,
    
- **so that** I can easily and securely extend the agent's capabilities.
    

**Acceptance Criteria**

1. A `Tooling` module is created that provides a `deftool` macro for declaratively defining tools that conform to the `Tool` behaviour.
    
2. A `FileSystem` tool module is created using the new DSL.
    
3. A `:read_file` tool is defined that takes a `path` argument.
    
4. The tool's `execute` logic validates the provided path against a pre-configured list of allowed directories, returning an error if the path is not permitted.
    
5. The `Agent` GenServer is updated to pass available tool definitions to the LLMProvider and correctly parse and execute a tool-use request from the LLM.
    
6. A tutorial for this story, explaining Elixir metaprogramming and the secure tool implementation, is created in `tutorials/epic1/story1.5/` and the main `tutorials/index.md` is updated.
    

### Story 1.6: Epic 1 Demo Creation

- **As a** Developer,
    
- **I want** a runnable demo for the core agent engine,
    
- **so that** I can easily showcase and verify the functionality of Epic 1.
    

**Acceptance Criteria**

1. A directory `demos/epic1/` is created.
    
2. An Elixir script (`.exs`) is created within the directory that starts the application, spawns an agent, and runs a pre-defined conversation demonstrating both a simple LLM call and a successful file tool call.
    
3. A `README.md` is created in `demos/epic1/` explaining how to configure and run the demo.
    
4. The demo script executes successfully and prints the expected output to the console.
    
5. A tutorial for this story, explaining how to create and run such demos, is created in `tutorials/epic1/story1.6/` and the main `tutorials/index.md` is updated.
    

## Epic 2: Phoenix LiveView UI & User Authentication

This epic focuses on building the primary user-facing component of our application: the real-time web interface. We will add the Phoenix framework, create the core UI, and implement a **configurable** secure OAuth flow. By the end of this epic, a user will be able to either log in or access the agent directly in a single-user mode.

### Story 2.1: Phoenix Project Integration & Basic Layout

- **As a** Developer,
    
- **I want** to add Phoenix to our project and create a basic application layout,
    
- **so that** we have a foundation for building the web interface.
    

**Acceptance Criteria**

1. The `phoenix` and `phoenix_live_view` libraries are added as dependencies to the Mix project.
    
2. A basic Phoenix application structure is generated within the existing project (e.g., in `lib/my_app_web/`).
    
3. A root layout is created with a simple header and a main content area where LiveViews will be rendered.
    
4. A basic "Home" LiveView is created and successfully renders at the root URL (`/`).
    
5. A tutorial for this story is created in `tutorials/epic2/story2.1/`, and the main `tutorials/index.md` is updated.
    

### Story 2.2: Configurable Web User Authentication

- **As a** Developer,
    
- **I want** to implement a configurable authentication flow,
    
- **so that** the application can support both secure multi-user and simple single-user modes.
    

**Acceptance Criteria**

1. The `ueberauth` and `ueberauth_google` libraries are added as dependencies.
    
2. An application setting (e.g., in `config/config.exs`) exists to enable or disable the authentication requirement.
    
3. **If authentication is enabled**, Phoenix routes and an `AuthController` are configured to handle the Google OAuth flow, and access to the agent page is protected.
    
4. **If authentication is enabled**, the UI shows "Login"/"Logout" buttons.
    
5. **If authentication is disabled**, users can access the agent page directly without being prompted to log in, and the "Login" button is not displayed.
    
6. A tutorial for this story is created in `tutorials/epic2/story2.2/`, and the main `tutorials/index.md` is updated.
    

### Story 2.3: Main Agent LiveView Interface for All Users

- **As a** User,
    
- **I want** a chat interface where I can send prompts to my agent and see its responses,
    
- **so that** I can interact with the AI, whether I am logged in or not.
    

**Acceptance Criteria**

1. An `AgentLive` LiveView is created and mounted at the `/agent` route.
    
2. **If authentication is enabled**, the LiveView starts or finds an `Agent` GenServer associated with the logged-in user's ID.
    
3. **If authentication is disabled**, the LiveView starts or finds an `Agent` GenServer associated with the user's browser session.
    
4. The LiveView contains a form for submitting prompts and renders the conversation history from the correct `Agent` process.
    
5. Submitting the form sends a message to the user's `Agent` process, and the LiveView correctly receives asynchronous messages back to update the UI.
    
6. A tutorial for this story is created in `tutorials/epic2/story2.3/`, and the main `tutorials/index.md` is updated.
    

### Story 2.4: Real-time Streaming & Status Updates

- **As a** User,
    
- **I want** to see the agent's responses stream in word-by-word and get visual feedback when it's using a tool,
    
- **so that** the interface feels alive and transparent.
    

**Acceptance Criteria**

1. The `Agent` GenServer sends asynchronous status messages (`:stream_chunk`, `:tool_call_start`, etc.) to the `AgentLive` process.
    
2. The LiveView uses Phoenix `streams` to efficiently append the streaming text to the current response in the UI.
    
3. The LiveView displays a clear loading indicator or message (e.g., "Using tool: read_file...") when a tool call is in progress.
    
4. The final, structured output from the tool call is rendered correctly in the chat history.
    
5. A tutorial for this story is created in `tutorials/epic2/story2.4/`, and the main `tutorials/index.md` is updated.
    

### Story 2.5: CLI Device Authorization Flow Backend

- **As a** CLI User,
    
- **I want** to authenticate my terminal session by visiting a URL in my browser,
    
- **so that** I don't have to handle credentials directly in the terminal.
    

**Acceptance Criteria**

1. A new set of API endpoints (e.g., `/api/cli/auth/...`) is created to handle a device authorization flow.
    
2. The backend can generate a device code and a user-facing URL for authorization.
    
3. A polling endpoint is created that a CLI client can use to check for successful authorization.
    
4. Once the user authorizes via the browser, the polling endpoint returns a valid access token to the CLI client.
    
5. A tutorial for this story is created in `tutorials/epic2/story2.5/`, and the main `tutorials/index.md` is updated.
    

### Story 2.6: Epic 2 Demo Creation

- **As a** Developer,
    
- **I want** a guide on how to run the web application locally in both authenticated and anonymous modes,
    
- **so that** I can easily showcase and verify the functionality of Epic 2.
    

**Acceptance Criteria**

1. A directory `demos/epic2/` is created with a `README.md` file.
    
2. The README explains how to configure the necessary environment variables for both modes.
    
3. The README provides the `mix phx.server` command and a step-by-step guide to log in (if enabled), send a prompt, and see a streaming response.
    
4. A tutorial for this story is created in `tutorials/epic2/story2.6/`, and the main `tutorials/index.md` is updated.
    

## Epic 3: Advanced Agent Capabilities & Tooling

This epic transforms our agent from a simple conversationalist into a powerful, multi-modal assistant. We will add support for more LLM providers with flexible authentication, implement the full suite of advanced, securely sandboxed tools (File System, Shell, OpenAPI), and introduce session persistence so users can save and load their conversations. This epic is focused on delivering the core power-user features of the application.

### Story 3.1: OpenAI & Anthropic LLM Adapters

- **As a** Developer,
    
- **I want** to add `LLMProvider` adapters for OpenAI and Anthropic with flexible authentication,
    
- **so that** the agent can connect to these providers using either API keys or user-level OAuth.
    

**Acceptance Criteria**

1. The `openai_ex` and `anthropix` libraries are added as dependencies.
    
2. New modules, `MyApp.Providers.OpenAI` and `MyApp.Providers.Anthropic`, are created that correctly implement the `LLMProvider` behaviour.
    
3. Both the OpenAI and Anthropic adapters must support authentication via direct API Key and via user-delegated OAuth tokens.
    
4. The application configuration is updated to allow selecting the active LLM provider and their authentication method.
    
5. The `Agent` GenServer can successfully use the new adapters to get text responses and process tool calls using either authentication method.
    
6. A tutorial for this story is created in `tutorials/epic3/story3.1/`, and the main `tutorials/index.md` is updated.
    

### Story 3.2: Full File System Tool (Write & List)

- **As an** Agent,
    
- **I want** to be able to write to files and list directory contents,
    
- **so that** I can perform more complex filesystem operations for the user.
    

**Acceptance Criteria**

1. The `FileSystem` tool module is updated with `:write_file` and `:list_directory` tools using the `deftool` DSL.
    
2. The `execute` logic for both new tools validates all paths against the configured allowed directory list.
    
3. The `:write_file` tool takes a `path` and `content` and securely writes the content to the specified file.
    
4. The `:list_directory` tool takes a `path` and returns a list of its files and subdirectories.
    
5. A tutorial for this story is created in `tutorials/epic3/story3.2/`, and the main `tutorials/index.md` is updated.
    

### Story 3.3: Sandboxed Shell Command Tool

- **As an** Agent,
    
- **I want** to execute shell commands in a sandboxed environment,
    
- **so that** I can perform system-level tasks safely for the user.
    

**Acceptance Criteria**

1. A `Shell` tool module is created using the `deftool` DSL with an `:execute_command` tool.
    
2. The tool's execution is sandboxed (e.g., using a Docker container) to prevent dangerous operations.
    
3. The application's settings provide flags to enable/disable this tool and to bypass the sandbox.
    
4. If the tool is disabled in the settings, it returns an informative error to the agent.
    
5. A tutorial for this story is created in `tutorials/epic3/story3.3/`, and the main `tutorials/index.md` is updated.
    

### Story 3.4: OpenAPI Specification Tool

- **As an** Agent,
    
- **I want** to be able to read an OpenAPI specification and make API calls based on it,
    
- **so that** I can interact with external web services on the user's behalf.
    

**Acceptance Criteria**

1. An `OpenAPI` tool module is created using the `deftool` DSL.
    
2. The tool can be initialized with the path or URL to an OpenAPI spec file.
    
3. The tool provides a function (e.g., `:call_api`) that accepts an `operation_id` and `arguments`.
    
4. The tool validates the arguments against the spec, constructs the correct HTTP request, and executes it.
    
5. The JSON response from the API call is returned to the agent.
    
6. A tutorial for this story is created in `tutorials/epic3/story3.4/`, and the main `tutorials/index.md` is updated.
    

### Story 3.5: Conversation Checkpointing (Save/Restore)

- **As a** User,
    
- **I want** to save my current conversation and restore it later,
    
- **so that** I don't lose my work between sessions.
    

**Acceptance Criteria**

1. The `Agent` GenServer state is made fully serializable.
    
2. A persistence mechanism is implemented (e.g., using ETS or a database).
    
3. The `Agent` GenServer exposes public API functions for `:save_session` and `:restore_session`.
    
4. The LiveView UI is updated with "Save Session" and "Restore Session" controls.
    
5. A user can successfully save a session, start a new conversation, and then restore the previous session, correctly reloading the full message history.
    
6. A tutorial for this story is created in `tutorials/epic3/story3.5/`, and the main `tutorials/index.md` is updated.
    

### Story 3.6: Epic 3 Demo Creation

- **As a** Developer,
    
- **I want** a runnable demo showcasing the advanced agent capabilities,
    
- **so that** I can easily verify the functionality of Epic 3.
    

**Acceptance Criteria**

1. A directory `demos/epic3/` is created with a `README.md`.
    
2. The demo guide explains how to configure multiple LLM API keys and any other required settings.
    
3. The demo includes steps (either via script or web UI) to showcase switching LLM providers, using the file write/list and shell tools, and saving/restoring a session.
    
4. A tutorial for this story is created in `tutorials/epic3/story3.6/`, and the main `tutorials/index.md` is updated.
    

## Epic 4: Terminal User Interface (TUI)

This epic is dedicated to building the Terminal User Interface (TUI), delivering on the promise of a tool that is deeply integrated into a developer's command-line workflow. We will create a rich, interactive console application that connects to the same powerful agent engine built in the previous epics. By the end of this epic, the project will have achieved full feature parity with the original `gemini-cli`, offering both a modern web UI and a classic, powerful TUI.

### Story 4.1: TUI Framework Integration & Basic Display

- **As a** Developer,
    
- **I want** to integrate a TUI library and render a basic interface,
    
- **so that** we have a foundation for building the terminal application.
    

**Acceptance Criteria**

1. A TUI library (e.g., `ratatouille`) is added as a dependency.
    
2. A new executable is created (e.g., via `escript`) that launches the TUI application.
    
3. The TUI successfully launches and renders a static welcome message, a prompt input area, and a conversation history panel.
    
4. The application can be exited cleanly using a standard key combination (e.g., Ctrl-C).
    
5. A tutorial for this story is created in `tutorials/epic4/story4.1/`, and the main `tutorials/index.md` is updated.
    

### Story 4.2: Configurable TUI Authentication

- **As a** CLI User,
    
- **I want** to either log in or connect anonymously based on the app's configuration,
    
- **so that** I can have a seamless experience in both single-user and multi-user modes.
    

**Acceptance Criteria**

1. The TUI first reads the application setting to determine if authentication is required.
    
2. **If authentication is enabled**, the TUI initiates the device authorization flow (calling the backend, printing the URL, and polling for a token) when no valid local token is found.
    
3. **If authentication is enabled**, a retrieved token is stored securely on the local machine.
    
4. **If authentication is disabled**, the TUI bypasses the login flow entirely and proceeds directly to the main agent interface.
    
5. A tutorial for this story is created in `tutorials/epic4/story4.2/` that covers both modes, and the main `tutorials/index.md` is updated.
    

### Story 4.3: TUI Agent Interaction Loop

- **As a** CLI User,
    
- **I want** to send prompts and see responses in my terminal,
    
- **so that** I can have a conversation with my agent.
    

**Acceptance Criteria**

1. After authentication or in anonymous mode, the TUI starts or connects to the user's `Agent` GenServer process.
    
2. User input from the prompt area is captured and sent as a message to the `Agent` process.
    
3. The TUI receives asynchronous messages from the `Agent` and uses them to update the conversation history panel.
    
4. Streaming text responses are handled correctly, with the view updating as new text chunks arrive.
    
5. A tutorial for this story is created in `tutorials/epic4/story4.3/`, and the main `tutorials/index.md` is updated.
    

### Story 4.4: TUI Tool Status Display

- **As a** CLI User,
    
- **I want** to see when the agent is using a tool,
    
- **so that** I understand what it is doing in real-time.
    

**Acceptance Criteria**

1. The TUI correctly handles status messages (e.g., `:tool_call_start`) from the `Agent` process.
    
2. A status line or message area in the TUI displays indicators like "Using tool: read_file..." when a tool is active.
    
3. The structured output from a completed tool call is formatted for readability and rendered cleanly in the conversation history.
    
4. A tutorial for this story is created in `tutorials/epic4/story4.4/`, and the main `tutorials/index.md` is updated.
    

### Story 4.5: Epic 4 Demo Creation

- **As a** Developer,
    
- **I want** a guide on how to run and demonstrate the TUI application,
    
- **so that** I can easily showcase the complete CLI experience.
    

**Acceptance Criteria**

1. A directory `demos/epic4/` is created with a `README.md`.
    
2. The README explains any TUI-specific configuration, including how to run in authenticated vs. anonymous mode.
    
3. It provides a step-by-step guide to launch the TUI, authenticate (if needed), send a prompt that uses a tool, and see the streaming response.
    
4. A tutorial for this story is created in `tutorials/epic4/story4.5/`, and the main `tutorials/index.md` is updated.