# Source Tree Structure

## Repository Overview

The Maestro repository is a comprehensive monorepo containing the main Phoenix application and multiple sub-projects related to AI development tools and CLI interfaces.

```
/Users/jasonk/Development/the_maestro/
├── [Main Phoenix Application]
├── source/                    # Sub-projects and external tools
├── docs/                     # Project documentation
├── .bmad-core/              # BMad development framework
└── .claude/                 # Claude Code configuration
```

## Main Phoenix Application Structure

### Core Application Files
```
/Users/jasonk/Development/the_maestro/
├── mix.exs                  # Project configuration and dependencies
├── mix.lock                 # Locked dependency versions
├── CLAUDE.md                # Development guidelines and standards
├── AGENTS.md                # Agent configuration documentation
├── README.md                # Main project documentation
└── .formatter.exs           # Code formatting configuration
```

### Phoenix Web Application
```
lib/
├── the_maestro.ex           # Main application module
├── the_maestro/
│   ├── application.ex       # OTP application supervisor
│   ├── mailer.ex           # Email functionality
│   └── repo.ex             # Database repository
└── the_maestro_web/
    ├── the_maestro_web.ex  # Web module definitions
    ├── components/          # Reusable UI components
    │   ├── core_components.ex
    │   ├── layouts.ex
    │   └── layouts/
    │       └── root.html.heex
    ├── controllers/         # HTTP request handlers
    │   ├── error_html.ex
    │   ├── error_json.ex
    │   ├── page_controller.ex
    │   ├── page_html.ex
    │   └── page_html/
    │       └── home.html.heex
    ├── endpoint.ex          # HTTP endpoint configuration
    ├── gettext.ex          # Internationalization
    ├── router.ex           # Route definitions
    └── telemetry.ex        # Monitoring and metrics
```

### Configuration
```
config/
├── config.exs              # Base configuration
├── dev.exs                 # Development environment
├── prod.exs                # Production environment
├── runtime.exs             # Runtime configuration
└── test.exs                # Test environment
```

### Database and Static Assets
```
priv/
├── gettext/                # Translation files
│   ├── en/LC_MESSAGES/
│   │   └── errors.po
│   └── errors.pot
├── plts/                   # Dialyzer PLT files
│   ├── dialyzer.plt
│   └── dialyzer.plt.hash
├── repo/                   # Database files
│   ├── migrations/         # Database migrations
│   └── seeds.exs          # Database seeding
└── static/                 # Static web assets
    ├── favicon.ico
    ├── images/logo.svg
    └── robots.txt
```

### Frontend Assets
```
assets/
├── css/
│   └── app.css             # Main stylesheet
├── js/
│   └── app.js              # Main JavaScript
├── tsconfig.json           # TypeScript configuration
└── vendor/                 # Third-party assets
    ├── daisyui-theme.js
    ├── daisyui.js
    ├── heroicons.js
    └── topbar.js
```

### Testing
```
test/
├── test_helper.exs         # Test setup and configuration
├── support/                # Test utilities
│   ├── conn_case.ex        # Controller test helpers
│   └── data_case.ex        # Database test helpers
└── the_maestro_web/        # Web layer tests
    └── controllers/
        ├── error_html_test.exs
        ├── error_json_test.exs
        └── page_controller_test.exs
```

## Documentation Structure

### Architecture Documentation
```
docs/
├── architecture.md         # Main architecture overview
├── architecture/           # Detailed architecture docs (SHARDED)
│   ├── index.md
│   ├── overview.md
│   ├── coding-standards.md           # Project coding standards (references CLAUDE.md)
│   ├── tech-stack.md                # Technology stack decisions
│   ├── source-tree.md               # This document
│   ├── system-architecture-logical-view.md
│   ├── component-implementation-specifications.md
│   ├── data-flow-data-model.md
│   ├── process-view-concurrency.md
│   ├── deployment-infrastructure.md
│   ├── integration-architecture.md
│   ├── performance-architecture.md
│   ├── security-architecture.md
│   ├── security-error-handling.md
│   ├── quality-assurance-architecture.md
│   └── architectural-decision-records-adrs.md
├── prd.md                  # Main Product Requirements Document  
├── prd/                    # Detailed PRD sections (SHARDED)
│   ├── index.md
│   ├── introduction-goals.md
│   ├── the-problem-the-user.md
│   ├── scope-features-high-level-epics.md
│   ├── user-stories.md
│   ├── non-functional-requirements.md
│   ├── out-of-scope.md
│   ├── business-justification.md
│   ├── success-metrics-kpis.md
│   ├── timeline-roadmap.md
│   ├── dependencies-assumptions.md
│   ├── risk-assessment-mitigation.md
│   └── testing-strategy.md
└── stories/                # Development stories
    └── 1.1.story.md
```

### Quality Assurance Documentation  
```
docs/qa/
├── pre-push-validation-guide.md
├── qa-gate-template.yml
├── qa-integration-summary.md
├── test-failures-analysis.md
├── assessments/            # QA assessment reports
└── gates/                  # QA gate definitions
```

### Standards and Guidelines
```
docs/standards/
├── project-specific-rules.md
├── quality-standards.md
└── testing-strategies.md
```

### Development Hooks
```
docs/hooks/
└── pre-push-setup.md      # Git hook configuration guide
```

## BMad Development Framework

The `.bmad-core/` directory contains the BMad development methodology framework:

```
.bmad-core/
├── core-config.yaml        # BMad configuration
├── install-manifest.yaml   # Installation manifest
├── enhanced-ide-development-workflow.md
├── working-in-the-brownfield.md
├── user-guide.md
├── agents/                 # Agent personalities
│   ├── analyst.md
│   ├── architect.md
│   ├── bmad-master.md
│   ├── bmad-orchestrator.md
│   ├── dev.md
│   ├── pm.md
│   ├── po.md
│   ├── qa.md
│   ├── sm.md
│   └── ux-expert.md
├── agent-teams/            # Team configurations
│   ├── team-all.yaml
│   ├── team-fullstack.yaml
│   ├── team-ide-minimal.yaml
│   └── team-no-ui.yaml
├── checklists/             # Quality checklists
│   ├── architect-checklist.md
│   ├── change-checklist.md
│   ├── pm-checklist.md
│   ├── po-master-checklist.md
│   ├── story-dod-checklist.md
│   └── story-draft-checklist.md
├── data/                   # Knowledge base
│   ├── bmad-kb.md
│   ├── brainstorming-techniques.md
│   ├── elicitation-methods.md
│   ├── technical-preferences.md
│   ├── test-levels-framework.md
│   └── test-priorities-matrix.md
├── tasks/                  # Executable workflows
│   ├── advanced-elicitation.md
│   ├── apply-qa-fixes.md
│   ├── brownfield-create-epic.md
│   ├── brownfield-create-story.md
│   ├── correct-course.md
│   ├── create-brownfield-story.md
│   ├── create-deep-research-prompt.md
│   ├── create-doc.md
│   ├── create-next-story.md
│   ├── document-project.md
│   ├── execute-checklist.md
│   ├── facilitate-brainstorming-session.md
│   ├── generate-ai-frontend-prompt.md
│   ├── index-docs.md
│   ├── kb-mode-interaction.md
│   ├── nfr-assess.md
│   ├── qa-gate.md
│   ├── review-story.md
│   ├── risk-profile.md
│   ├── shard-doc.md
│   ├── test-design.md
│   ├── trace-requirements.md
│   └── validate-next-story.md
├── templates/              # Document templates
│   ├── architecture-tmpl.yaml
│   ├── brainstorming-output-tmpl.yaml
│   ├── brownfield-architecture-tmpl.yaml
│   ├── brownfield-prd-tmpl.yaml
│   ├── competitor-analysis-tmpl.yaml
│   ├── front-end-architecture-tmpl.yaml
│   ├── front-end-spec-tmpl.yaml
│   ├── fullstack-architecture-tmpl.yaml
│   ├── market-research-tmpl.yaml
│   ├── prd-tmpl.yaml
│   ├── project-brief-tmpl.yaml
│   ├── qa-gate-tmpl.yaml
│   └── story-tmpl.yaml
├── utils/                  # Utilities
│   ├── bmad-doc-template.md
│   └── workflow-management.md
└── workflows/              # Workflow definitions
    ├── brownfield-fullstack.yaml
    ├── brownfield-service.yaml
    ├── brownfield-ui.yaml
    ├── greenfield-fullstack.yaml
    ├── greenfield-service.yaml
    └── greenfield-ui.yaml
```

## Claude Code Configuration

The `.claude/` directory contains Claude Code specific configurations:

```
.claude/
├── agents/                 # Claude-specific agents
│   ├── code-reviewer.md
│   └── qa-expert.md
└── commands/               # Custom commands
    ├── BMad/              # BMad command integrations
    │   ├── agents/        # Agent definitions
    │   └── tasks/         # Task definitions
    ├── agent-os-execute.md
    ├── develop.md
    ├── draft.md
    ├── handover-project-level.md
    ├── push-it.md
    ├── review.md
    └── validate.md
```

## Source Sub-Projects

The `source/` directory contains external tools and sub-projects:

### Gemini CLI Tool
```
source/gemini-cli/
├── README.md
├── package.json            # Node.js project configuration
├── docs/                   # Comprehensive documentation
├── packages/               # Modular packages
├── integration-tests/      # Test suites
└── scripts/                # Build and utility scripts
```

### LLXPRT Code Tool
```
source/llxprt-code/
├── README.md
├── package.json            # Node.js project configuration
├── docs/                   # Documentation
├── packages/               # Modular packages
├── integration-tests/      # Test suites
├── project-plans/          # Detailed project planning
└── scripts/                # Build and utility scripts
```

### Legacy Reference
```
source/the_maestro/         # Legacy version for reference
├── README.md
├── mix.exs
├── lib/
├── config/
└── [Standard Phoenix structure]
```

## Build and Runtime Structure

### Generated Files
```
_build/                     # Compiled Elixir code (gitignored)
deps/                       # Downloaded dependencies (gitignored)
logs/                       # Application logs (gitignored)
```

## Key Configuration Files

### Project Configuration
- **mix.exs**: Main project configuration, dependencies, aliases
- **CLAUDE.md**: Comprehensive development guidelines and standards
- **.formatter.exs**: Code formatting rules for `mix format`
- **config/**: Environment-specific configuration

### BMad Integration  
- **.bmad-core/core-config.yaml**: BMad framework configuration
- **devLoadAlwaysFiles**: Files automatically loaded during development
- **prdSharded**: Indicates PRD documentation is split into multiple files
- **architectureSharded**: Indicates architecture docs are split into multiple files

### Development Tooling
- **Git hooks**: Pre-push validation ensuring code quality
- **Dialyzer**: Static analysis with PLT files in `priv/plts/`
- **Credo**: Code quality and style checking
- **Mix aliases**: `precommit` for running all quality checks

## File Naming Conventions

### Documentation
- **Sharded Documents**: Main file (e.g., `prd.md`) with detail files in subdirectory (e.g., `prd/`)
- **Architecture Files**: Descriptive names following component patterns
- **Stories**: Numbered format (`1.1.story.md`)

### Code Files
- **Phoenix Modules**: Follow Phoenix naming conventions
- **Test Files**: Mirror `lib/` structure with `_test.exs` suffix
- **Configuration**: Environment-specific names (`dev.exs`, `prod.exs`, `test.exs`)

## Dependencies and Build System

### Main Dependencies (from mix.exs)
- **Phoenix 1.8.0**: Web framework
- **Ecto & PostgreSQL**: Database layer  
- **LiveView 1.1.0**: Interactive UI components
- **Req 0.5**: HTTP client (preferred over Tesla/HTTPoison)
- **Tailwind & Heroicons**: Frontend styling and icons
- **Credo & Dialyxir**: Code quality tools

### Development Workflow
1. **Research**: Use Archon MCP for documentation and examples
2. **Code**: Follow CLAUDE.md guidelines and coding-standards.md
3. **Test**: Comprehensive testing with proper assertions
4. **Quality**: Run `mix precommit` before committing
5. **Commit**: Never bypass git hooks, fix issues instead

This source tree structure supports a comprehensive development workflow with clear separation of concerns, comprehensive documentation, and integration with modern development tools and methodologies.