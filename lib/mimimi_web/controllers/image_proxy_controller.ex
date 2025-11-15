defmodule MimimiWeb.ImageProxyController do
  use MimimiWeb, :controller
  require Logger

  @rails_base_url System.get_env("WORTSCHULE_RAILS_URL") || "https://wort.schule"

  def show(conn, %{"path" => path}) do
    # path is a list from the glob pattern, join it with /
    # URL encode each path segment to handle spaces and special characters
    encoded_path = Enum.map_join(path, "/", &URI.encode_www_form/1)
    path_str = "/" <> encoded_path
    url = "#{@rails_base_url}#{path_str}"

    Logger.debug("[ImageProxy] Fetching: #{url}")

    # Req follows redirects by default
    case Req.get(url) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type = get_content_type(headers)
        Logger.debug("[ImageProxy] Success: #{content_type}, #{byte_size(body)} bytes")

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000")
        |> send_resp(200, body)

      {:ok, %{status: status}} ->
        Logger.warning("[ImageProxy] Non-200 status: #{status} for #{url}")
        send_resp(conn, status, "")

      {:error, reason} ->
        Logger.error("[ImageProxy] Error fetching #{url}: #{inspect(reason)}")
        send_resp(conn, 502, "Bad Gateway")
    end
  end

  defp get_content_type(headers) do
    headers
    |> extract_content_type()
    |> normalize_content_type()
  end

  defp extract_content_type(%{} = header_map) do
    # Map format: %{"content-type" => ["image/png"]} or %{"content-type" => "image/png"}
    Map.get(header_map, "content-type") || Map.get(header_map, :content_type)
  end

  defp extract_content_type(headers) when is_list(headers) do
    # List format: [{"content-type", ["image/png"]}] or [{"content-type", "image/png"}]
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == "content-type", do: value

      _ ->
        nil
    end)
  end

  defp normalize_content_type([value | _]) when is_binary(value), do: value
  defp normalize_content_type(value) when is_binary(value), do: value
  defp normalize_content_type(_), do: "application/octet-stream"
end
