#!/usr/bin/env python3
"""Quick test to verify SSE final frame handling"""
import asyncio
import os
import sys

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))

from maestro_tui.api.client import MaestroAPI
from maestro_tui.config import ApiConfig
from maestro_tui.orchestrator import send_and_orchestrate


async def main():
    print("🔍 Testing SSE final frame handling...")
    print("=" * 80)

    # Load API config
    config_path = os.path.expanduser("~/.the_maestro/config.json")
    if not os.path.exists(config_path):
        print(f"❌ Config not found at {config_path}")
        return

    import json
    with open(config_path) as f:
        cfg_data = json.load(f)

    cfg = ApiConfig(
        api_key=cfg_data["api_key"],
        api_host=cfg_data.get("api_host", "http://localhost:4000")
    )

    api = MaestroAPI(cfg)

    try:
        # Create a test session
        print("📝 Creating test session...")
        providers = await api.list_providers()
        print(f"   Available providers: {providers}")

        # Use Anthropic if available
        provider = "anthropic" if "anthropic" in providers else providers[0]
        auths = await api.list_saved_auths(provider)
        if not auths:
            print(f"❌ No saved auth for {provider}")
            return

        auth_id = auths[0]["id"]
        models = await api.list_models(provider, auth_id)
        model = models[0] if models else "claude-3-5-sonnet-20241022"

        print(f"   Using: provider={provider}, model={model}")

        session_id = await api.create_session(
            auth_id=auth_id,
            model_id=model,
            working_dir=os.getcwd(),
            tool_runtime="remote"
        )
        print(f"   Session created: {session_id}")

        # Send a message that will use a tool
        print("\n🚀 Sending tool-using message...")
        message = "please list the files in your directory"

        messages = await send_and_orchestrate(
            api,
            session_id=session_id,
            message=message,
            provider=provider,
            base_dir=os.getcwd(),
        )

        print(f"\n✅ Received {len(messages)} messages:")
        for i, msg in enumerate(messages, 1):
            role = msg.get("role", "unknown")
            text = msg.get("text", "")
            preview = text[:100] + "..." if len(text) > 100 else text
            print(f"   {i}. [{role}] {preview}")

        # Check if we got the final assistant response
        assistant_msgs = [m for m in messages if m.get("role") == "assistant"]
        if not assistant_msgs:
            print("\n❌ FAILED: No assistant messages found!")
            return

        last_assistant = assistant_msgs[-1]
        text = last_assistant.get("text", "")
        if "[tool:" in text:
            print(f"\n⚠️  WARNING: Last assistant message is a tool call, not final response")
            print(f"   Content: {text[:200]}")
        else:
            print(f"\n✅ SUCCESS: Got final assistant response ({len(text)} chars)")
            print(f"   Preview: {text[:200]}")

        # Clean up
        await api.delete_session(session_id)
        print(f"\n🧹 Session cleaned up")

    finally:
        await api.close()

    print("\n" + "=" * 80)
    print("📊 Check logs at: /tmp/maestro_tui_sse_debug.log")


if __name__ == "__main__":
    asyncio.run(main())
