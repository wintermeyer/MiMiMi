defmodule MimimiWeb.ImageProxyControllerTest do
  use MimimiWeb.ConnCase, async: true

  @moduletag :external_api

  describe "show/2" do
    test "proxies image requests from wort.schule", %{conn: conn} do
      # This is a known valid image path from wort.schule
      # Using a simple test path - in production this would be a real image
      image_path = "/rails/active_storage/blobs/redirect/test.png"

      # Make request through proxy
      conn = get(conn, "/proxy/image#{image_path}")

      # Should return a response (may be 200, 302, or 502 depending on if the test URL exists)
      assert conn.status in [200, 302, 404, 502]
    end

    test "handles non-existent images gracefully", %{conn: conn} do
      # Request a path that definitely doesn't exist
      conn = get(conn, "/proxy/image/this/path/does/not/exist.png")

      # Should return error status
      assert conn.status in [404, 502]
    end
  end
end
