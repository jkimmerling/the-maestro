# Environment Variable Migration Guide

- OPENAI_API_KEY → used by Provider API key sessions
- OPENAI_OAUTH_SESSION → named OAuth session for OpenAI
- ANTHROPIC_API_KEY / ANTHROPIC_OAUTH_SESSION → Anthropic sessions
- GEMINI_OAUTH_SESSION / GOOGLE_API_KEY → Gemini sessions (OAuth or API key)
- *_MODEL → model selection per provider (e.g., OPENAI_MODEL, ANTHROPIC_MODEL, GEMINI_MODEL)

Use the unified scripts in `scripts/` which read these variables consistently.

