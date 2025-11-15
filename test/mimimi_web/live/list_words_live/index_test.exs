defmodule MimimiWeb.ListWordsLive.IndexTest do
  use MimimiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "list words page" do
    test "renders list words page with filter", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/list_words")

      # Should show the list words header
      assert html =~ "Wörterliste"

      # Should have filter control
      assert has_element?(view, "#keyword-filter")
    end

    test "filter updates when changed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/list_words")

      # Change filter to 2 keywords minimum by triggering the form's phx-change event
      view
      |> element("form")
      |> render_change(%{"min_keywords" => "2"})

      # Verify the filter value is displayed
      assert render(view) =~ "Mindestanzahl Schlüsselwörter: 2"
    end

    test "displays loading state initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/list_words")

      # Should show loading count
      assert html =~ "Wörter geladen"
    end

    @tag :external_db
    test "slider max value is set to maximum keywords count", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/list_words")

      # Should have slider with max attribute
      assert has_element?(view, "#keyword-filter")

      # Get the max keywords count from the database
      max_count = Mimimi.WortSchule.get_max_keywords_count()
      max_count = max(max_count, 1)

      # Check that the slider max is set correctly in the HTML
      assert html =~ "max=\"#{max_count}\""

      # Check that the max value label displays correctly
      assert html =~ "<span>#{max_count}</span>"
    end
  end
end
