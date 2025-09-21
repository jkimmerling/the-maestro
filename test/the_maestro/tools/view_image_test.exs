defmodule TheMaestro.Tools.ViewImageTest do
  use TheMaestro.DataCase, async: true

  alias TheMaestro.{Conversations, Auth, Images}

  setup do
    {:ok, saved_auth} =
      Auth.create_saved_authentication(%{
        provider: "openai",
        auth_type: :api_key,
        name: "openai-img-test",
        credentials: %{"api_key" => "sk-test"},
        expires_at: DateTime.utc_now()
      })

    {:ok, session} =
      Conversations.create_session(%{
        name: "Image Tool Test",
        auth_id: saved_auth.id,
        working_dir: File.cwd!()
      })

    # create temp image file
    base = File.cwd!()
    path = Path.join(base, "tmp/test-image.png")
    File.rm_rf!(Path.dirname(path))
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, <<137, 80, 78, 71, 13, 10, 26, 10>>) # PNG signature

    {:ok, %{session: session, img_path: path}}
  end

  test "stores attachment in redis", %{session: session, img_path: img} do
    args = %{"path" => Path.relative_to(img, File.cwd!())}
    assert {:ok, _} = TheMaestro.Tools.ViewImage.run(args, session_id: session.id)

    items = Images.list(session.id)
    assert Enum.any?(items, fn it -> (it["path"] || it[:path]) == img end)
  end
end
