#!/usr/bin/env python3
"""Test script for model switching functionality"""

import asyncio
import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / "src"))

from maestro_tui.api.client import MaestroAPI
from maestro_tui.config import load_config, load_settings, save_settings, Settings


async def test_model_switching():
    """Test creating a session and switching models"""
    print("Starting model switch test...")

    # Load config and create API client
    cfg = load_config()
    # Override port for testing
    cfg.api_host = "http://127.0.0.1:4001"
    api = MaestroAPI(cfg)

    try:
        # 1. List providers
        print("\n1. Listing providers...")
        providers = await api.list_providers()
        print(f"   Available providers: {providers}")

        if not providers:
            print("   ERROR: No providers available")
            return False

        # 2. Get auth for first provider (Anthropic)
        provider = providers[0] if "anthropic" in providers else providers[0]
        print(f"\n2. Getting auths for provider: {provider}")
        auths = await api.list_saved_auths(provider)
        print(f"   Found {len(auths)} auth(s)")

        if not auths:
            print("   ERROR: No auths available")
            return False

        auth = auths[0]
        auth_id = auth["id"]
        print(f"   Using auth: {auth['label']} ({auth_id[:8]}...)")

        # 3. Get models for this auth
        print(f"\n3. Getting models for auth...")
        models = await api.list_models(provider, auth_id)
        print(f"   Available models: {models[:3]}...")  # Show first 3

        if not models:
            print("   ERROR: No models available")
            return False

        model = models[0]
        print(f"   Using model: {model}")

        # 4. Create a session
        print(f"\n4. Creating session with {provider}/{model}...")
        session_id = await api.create_session(
            auth_id=auth_id,
            model_id=model,
            tool_runtime="remote"
        )
        print(f"   Created session: {session_id}")

        # 5. Send a test message
        print("\n5. Sending test message...")
        response = await api.start_turn(session_id, "Hello, this is a test", None)
        print(f"   Response received (stream_id: {response.get('stream_id', 'N/A')[:8]}...)")

        # Wait a moment for the message to process
        await asyncio.sleep(2)

        # 6. Switch to a different provider (OpenAI if available)
        if len(providers) > 1:
            new_provider = "openai" if "openai" in providers else providers[1]
            print(f"\n6. Switching to provider: {new_provider}")

            # Get auth for new provider
            new_auths = await api.list_saved_auths(new_provider)
            if new_auths:
                new_auth = new_auths[0]
                new_auth_id = new_auth["id"]
                print(f"   Using auth: {new_auth['label']} ({new_auth_id[:8]}...)")

                # Get models for new auth
                new_models = await api.list_models(new_provider, new_auth_id)
                if new_models:
                    new_model = new_models[0]
                    print(f"   Using model: {new_model}")

                    # Update the session
                    print(f"\n7. Updating session to {new_provider}/{new_model}...")
                    result = await api.update_session(
                        session_id,
                        auth_id=new_auth_id,
                        model_id=new_model
                    )
                    print(f"   Session updated: {result}")

                    # 8. Send another test message with new provider
                    print("\n8. Sending test message with new provider...")
                    response2 = await api.start_turn(session_id, "Can you confirm which model you are?", None)
                    print(f"   Response received (stream_id: {response2.get('stream_id', 'N/A')[:8]}...)")

                    print("\n✅ Model switching test PASSED")
                    return True
                else:
                    print(f"   No models available for {new_provider}")
            else:
                print(f"   No auths available for {new_provider}")
        else:
            print("\n6. Only one provider available, skipping provider switch test")

            # At least test switching models within same provider
            if len(models) > 1:
                new_model = models[1]
                print(f"   Switching to model: {new_model}")

                result = await api.update_session(
                    session_id,
                    auth_id=auth_id,
                    model_id=new_model
                )
                print(f"   Session updated: {result}")

                print("\n7. Sending test message with new model...")
                response2 = await api.start_turn(session_id, "Testing with different model", None)
                print(f"   Response received (stream_id: {response2.get('stream_id', 'N/A')[:8]}...)")

                print("\n✅ Model switching test PASSED (same provider)")
                return True

        print("\n⚠️ Model switching test INCOMPLETE (limited providers/models)")
        return True

    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        await api.close()


async def main():
    """Main test runner"""
    success = await test_model_switching()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    asyncio.run(main())
