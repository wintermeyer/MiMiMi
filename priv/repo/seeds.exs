# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Mimimi.Repo.insert!(%Mimimi.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Mimimi.Repo
alias Mimimi.Games.{Word, Keyword}

# Clear existing data
Repo.delete_all(Keyword)
Repo.delete_all(Word)

# German words with keywords in einfache Sprache (simple language for children)
words_data = [
  # Tiere (Animals)
  {"Hund", ["Tier", "bellt", "treu", "Haustier", "Gassi"]},
  {"Katze", ["Tier", "miaut", "Fell", "Haustier", "schnurrt"]},
  {"Elefant", ["groß", "Rüssel", "grau", "Tier", "stark"]},
  {"Löwe", ["wild", "brüllt", "Mähne", "Tier", "König"]},
  {"Maus", ["klein", "Tier", "piepst", "grau", "Schwanz"]},
  {"Vogel", ["fliegt", "Flügel", "singt", "Tier", "Nest"]},
  {"Fisch", ["schwimmt", "Wasser", "Tier", "Schuppen", "Flosse"]},
  {"Pferd", ["Tier", "groß", "galoppiert", "Mähne", "reiten"]},
  {"Kuh", ["Tier", "muht", "Milch", "Weide", "Flecken"]},
  {"Schaf", ["Tier", "Wolle", "Weide", "weiß", "bäht"]},

  # Obst (Fruits)
  {"Apfel", ["Obst", "rot", "rund", "süß", "Baum"]},
  {"Banane", ["Obst", "gelb", "lang", "süß", "schälen"]},
  {"Orange", ["Obst", "rund", "orange", "saftig", "Vitamin"]},
  {"Erdbeere", ["Obst", "rot", "klein", "süß", "Sommer"]},
  {"Kirsche", ["Obst", "rot", "klein", "rund", "Kern"]},
  {"Birne", ["Obst", "süß", "grün", "saftig", "Baum"]},
  {"Traube", ["Obst", "klein", "rund", "lila", "Wein"]},

  # Gemüse (Vegetables)
  {"Karotte", ["Gemüse", "orange", "lang", "Wurzel", "knackig"]},
  {"Tomate", ["Gemüse", "rot", "rund", "saftig", "Salat"]},
  {"Gurke", ["Gemüse", "grün", "lang", "frisch", "Wasser"]},
  {"Kartoffel", ["Gemüse", "braun", "Erde", "kochen", "rund"]},
  {"Paprika", ["Gemüse", "rot", "grün", "knackig", "süß"]},
  {"Salat", ["Gemüse", "grün", "Blätter", "frisch", "gesund"]},

  # Fahrzeuge (Vehicles)
  {"Auto", ["fährt", "Räder", "Motor", "Straße", "schnell"]},
  {"Bus", ["fährt", "groß", "Räder", "viele Menschen", "Straße"]},
  {"Fahrrad", ["fährt", "Räder", "treten", "langsam", "gesund"]},
  {"Zug", ["fährt", "Schienen", "lang", "schnell", "Bahnhof"]},
  {"Flugzeug", ["fliegt", "Himmel", "schnell", "Flügel", "hoch"]},
  {"Schiff", ["schwimmt", "Wasser", "groß", "Meer", "langsam"]},
  {"Roller", ["fährt", "klein", "Räder", "Kinder", "treten"]},

  # Natur (Nature)
  {"Baum", ["Blätter", "groß", "Wald", "grün", "Stamm"]},
  {"Blume", ["Blüte", "schön", "Farbe", "Duft", "Wiese"]},
  {"Sonne", ["hell", "warm", "gelb", "Himmel", "Tag"]},
  {"Mond", ["Nacht", "hell", "rund", "Himmel", "leuchtet"]},
  {"Stern", ["Nacht", "Himmel", "funkelt", "klein", "hell"]},
  {"Wolke", ["Himmel", "weiß", "Regen", "weich", "fliegt"]},
  {"Regen", ["Wasser", "Tropfen", "nass", "Himmel", "Wolke"]},
  {"Schnee", ["weiß", "kalt", "Winter", "weich", "Flocken"]},

  # Essen & Trinken (Food & Drink)
  {"Brot", ["Essen", "braun", "backen", "schneiden", "lecker"]},
  {"Käse", ["Essen", "gelb", "Milch", "lecker", "weich"]},
  {"Wurst", ["Essen", "Fleisch", "rund", "schneiden", "Brot"]},
  {"Ei", ["Essen", "weiß", "rund", "Huhn", "kochen"]},
  {"Milch", ["Trinken", "weiß", "Kuh", "Glas", "gesund"]},
  {"Wasser", ["Trinken", "klar", "nass", "Durst", "Flasche"]},
  {"Saft", ["Trinken", "Obst", "süß", "Flasche", "Glas"]},
  {"Kuchen", ["Essen", "süß", "backen", "lecker", "Geburtstag"]},

  # Schule & Lernen (School & Learning)
  {"Buch", ["lesen", "Seiten", "Wörter", "lernen", "Geschichte"]},
  {"Stift", ["schreiben", "Farbe", "malen", "dünn", "Papier"]},
  {"Heft", ["Seiten", "schreiben", "Schule", "Papier", "liniert"]},
  {"Tafel", ["schwarz", "Kreide", "Schule", "Lehrer", "groß"]},
  {"Stuhl", ["sitzen", "Beine", "Schule", "Holz", "Tisch"]},
  {"Tisch", ["Platte", "Beine", "Schule", "Holz", "Stuhl"]},

  # Körper (Body)
  {"Hand", ["Finger", "greifen", "Arm", "fünf", "Körper"]},
  {"Fuß", ["gehen", "Zehen", "Bein", "Schuh", "Körper"]},
  {"Kopf", ["denken", "Haare", "Gesicht", "oben", "Körper"]},
  {"Auge", ["sehen", "Gesicht", "rund", "Farbe", "zwei"]},
  {"Ohr", ["hören", "Kopf", "Seite", "zwei", "Körper"]},
  {"Mund", ["sprechen", "essen", "Lippen", "Zähne", "Gesicht"]},
  {"Nase", ["riechen", "Gesicht", "Luft", "Mitte", "schnüffeln"]},

  # Haus & Möbel (House & Furniture)
  {"Haus", ["Wand", "Dach", "Tür", "wohnen", "groß"]},
  {"Tür", ["öffnen", "schließen", "Haus", "Holz", "Zimmer"]},
  {"Fenster", ["Glas", "durchsehen", "Haus", "hell", "Licht"]},
  {"Bett", ["schlafen", "weich", "Kissen", "Decke", "Zimmer"]},
  {"Schrank", ["Türen", "Kleidung", "groß", "aufbewahren", "Zimmer"]},
  {"Lampe", ["Licht", "hell", "leuchten", "Strom", "Zimmer"]}
]

# Insert words and keywords
Enum.each(words_data, fn {word_name, keywords_list} ->
  # Insert word (using emoji as placeholder for image_path)
  word =
    %Word{}
    |> Word.changeset(%{name: word_name, image_path: "emoji"})
    |> Repo.insert!()

  # Insert keywords
  Enum.each(keywords_list, fn keyword_name ->
    %Keyword{}
    |> Keyword.changeset(%{name: keyword_name, word_id: word.id})
    |> Repo.insert!()
  end)
end)

IO.puts("✓ Seeded #{length(words_data)} German words with keywords (einfache Sprache)")
