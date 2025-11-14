# Phoenix Application Integration Guide

This guide explains how to access wort.schule data from an external Phoenix Framework application via direct PostgreSQL database access.

## Table of Contents
- [Quick Start](#quick-start)
- [Database Configuration](#database-configuration)
- [Ecto Schema Definitions](#ecto-schema-definitions)
- [Query Examples](#query-examples)
- [Image URL Construction](#image-url-construction)
- [Database Schema Reference](#database-schema-reference)

---

## Quick Start

This guide focuses on the minimal setup needed to access word names, IDs, keywords, and image URLs.

### What You'll Get

```elixir
# Fetch a word with its keywords and image
word = YourApp.Wortschule.get_complete_word(123)

%{
  id: 123,
  name: "Affe",
  keywords: [
    %{id: 456, name: "Tier"},
    %{id: 789, name: "Säugetier"}
  ],
  image_url: "https://wort.schule/rails/active_storage/blobs/redirect/abc123/affe.png"
}
```

### Minimal Setup

1. **Configure database connection** (see [Database Configuration](#database-configuration))
2. **Define minimal Word schema** (see [Ecto Schema Definitions](#ecto-schema-definitions))
3. **Add Image helper** (see [Image URL Construction](#image-url-construction))
4. **Use the example module below:**

```elixir
# lib/your_app/wortschule.ex
defmodule YourApp.Wortschule do
  import Ecto.Query
  alias YourApp.WortschuleRepo, as: Repo
  alias YourApp.Wortschule.{Word, ImageHelper}

  @doc """
  Get complete word data: id, name, keywords, and image URL.
  """
  def get_complete_word(word_id) do
    case get_word_with_keywords(word_id) do
      nil -> {:error, :not_found}
      word -> {:ok, format_word(word)}
    end
  end

  defp get_word_with_keywords(word_id) do
    from(w in Word,
      where: w.id == ^word_id,
      preload: [keywords: ^from(k in Word, order_by: k.name)]
    )
    |> Repo.one()
  end

  defp format_word(word) do
    %{
      id: word.id,
      name: word.name,
      keywords: Enum.map(word.keywords, &%{id: &1.id, name: &1.name}),
      image_url: ImageHelper.image_url_for_word(word.id)
    }
  end
end
```

---

## Database Configuration

### Production Database Credentials

Add to your Phoenix app's `config/prod.exs` or `config/runtime.exs`:

```elixir
config :your_app, YourApp.WortschuleRepo,
  database: "wortschule_production",
  username: "wortschule",
  password: System.get_env("WORTSCHULE_DATABASE_PASSWORD"),
  hostname: "localhost",  # Or shared server IP
  port: 5432,
  pool_size: 10,
  queue_target: 50,
  queue_interval: 1000
```

### Repository Definition

Create a separate Ecto repository for wort.schule data:

```elixir
# lib/your_app/wortschule_repo.ex
defmodule YourApp.WortschuleRepo do
  use Ecto.Repo,
    otp_app: :your_app,
    adapter: Ecto.Adapters.Postgres
end
```

Add to your application supervision tree in `lib/your_app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    YourApp.Repo,           # Your app's repo
    YourApp.WortschuleRepo, # Wortschule read-only repo
    # ... other children
  ]

  opts = [strategy: :one_for_one, name: YourApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

---

## Ecto Schema Definitions

### Word Schema (Minimal)

For basic access to word names, IDs, and keywords, you only need a minimal schema:

```elixir
# lib/your_app/wortschule/word.ex
defmodule YourApp.Wortschule.Word do
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :id, autogenerate: true}
  schema "words" do
    field :name, :string
    field :slug, :string
    field :type, :string  # Optional: "Noun", "Verb", "Adjective", "FunctionWord"

    timestamps()

    # Many-to-many self-referential association for keywords
    many_to_many :keywords, __MODULE__,
      join_through: "keywords",
      join_keys: [word_id: :id, keyword_id: :id]
  end
end
```

**Note:** The `words` table contains many more fields (noun cases, verb conjugations, etc.) but you don't need to define them in your schema unless you plan to use them.


---

## Query Examples

```elixir
import Ecto.Query
alias YourApp.WortschuleRepo, as: Repo
alias YourApp.Wortschule.Word

# Get word by ID
def get_word(id) do
  Repo.get(Word, id)
end

# Get word by slug
def get_word_by_slug(slug) do
  Repo.get_by(Word, slug: slug)
end

# Get word with keywords preloaded
def get_word_with_keywords(id) do
  from(w in Word,
    where: w.id == ^id,
    preload: [keywords: ^from(k in Word, order_by: k.name)]
  )
  |> Repo.one()
end

# Search words by name
def search_words(search_term) do
  pattern = "%#{search_term}%"

  from(w in Word,
    where: ilike(w.name, ^pattern),
    order_by: w.name,
    limit: 20
  )
  |> Repo.all()
end

# Get all words with images
def get_words_with_images do
  from(w in Word,
    join: att in "active_storage_attachments",
      on: att.record_id == w.id and att.record_type == "Word" and att.name == "image",
    distinct: true,
    order_by: w.name
  )
  |> Repo.all()
end

# Check if a word has an image
def word_has_image?(word_id) do
  from(att in "active_storage_attachments",
    where: att.record_type == "Word" and
           att.record_id == ^word_id and
           att.name == "image"
  )
  |> Repo.exists?()
end
```

---

## Image URL Construction

ActiveStorage stores images and serves them through Rails. The simplest approach is to proxy image requests through the Rails application.

### Image Helper Module

```elixir
# lib/your_app/wortschule/image_helper.ex
defmodule YourApp.Wortschule.ImageHelper do
  import Ecto.Query
  alias YourApp.WortschuleRepo, as: Repo

  @rails_base_url System.get_env("WORTSCHULE_RAILS_URL") || "https://wort.schule"

  @doc """
  Get image URL for a word by proxying through Rails.
  Returns nil if no image attached.
  """
  def image_url_for_word(word_id) do
    case get_image_blob(word_id) do
      nil -> nil
      {key, filename} -> "#{@rails_base_url}/rails/active_storage/blobs/redirect/#{key}/#{filename}"
    end
  end

  @doc """
  Check if a word has an image.
  """
  def has_image?(word_id) do
    from(att in "active_storage_attachments",
      where: att.record_type == "Word" and
             att.record_id == ^word_id and
             att.name == "image"
    )
    |> Repo.exists?()
  end

  defp get_image_blob(word_id) do
    from(att in "active_storage_attachments",
      where: att.record_type == "Word" and
             att.record_id == ^word_id and
             att.name == "image",
      join: blob in "active_storage_blobs", on: blob.id == att.blob_id,
      select: {blob.key, blob.filename}
    )
    |> Repo.one()
  end
end
```

### Usage

```elixir
# Get image URL for a word
ImageHelper.image_url_for_word(123)
# => "https://wort.schule/rails/active_storage/blobs/redirect/abc123def456/word_image.png"

# Check if word has image
ImageHelper.has_image?(123)
# => true
```

---

## Database Schema Reference

### Main Tables

#### `words` Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key |
| `type` | string | STI discriminator (Noun, Verb, Adjective, FunctionWord) |
| `name` | string | The German word |
| `slug` | string | URL-friendly identifier (unique, indexed) |
| `meaning` | string | Short meaning |
| `meaning_long` | string | Detailed description |
| `syllables` | string | Phonetic syllable breakdown |
| `example_sentences` | jsonb | Array of example sentences |
| `hit_counter` | bigint | Page view tracking |
| `prototype` | boolean | Is prototype word |
| `foreign` | boolean | Foreign language word |
| `compound` | boolean | Compound word |
| `with_tts` | boolean | Text-to-speech enabled |
| `created_at` | timestamp | Record creation time |
| `updated_at` | timestamp | Last update time |

See the Word schema above for complete field list including type-specific fields.

#### `keywords` Table (Join Table)

| Column | Type | Description |
|--------|------|-------------|
| `word_id` | integer | Foreign key to words.id |
| `keyword_id` | integer | Foreign key to words.id (self-referential) |

**Indexes:**
- `index_keywords_on_word_id_and_keyword_id` (unique)
- `index_keywords_on_keyword_id_and_word_id` (unique, reverse)

#### `active_storage_attachments` Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key |
| `name` | string | Attachment name ("image" or "audios") |
| `record_type` | string | Polymorphic type ("Word") |
| `record_id` | bigint | Foreign key to words.id |
| `blob_id` | bigint | Foreign key to active_storage_blobs.id |
| `created_at` | timestamp | Record creation time |

**Indexes:**
- `index_active_storage_attachments_uniqueness` on `[name, record_type, record_id, blob_id]` (unique)
- `index_active_storage_attachments_on_blob_id`

#### `active_storage_blobs` Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key |
| `key` | string | Internal storage key (unique) |
| `filename` | string | Original filename |
| `content_type` | string | MIME type |
| `metadata` | text | JSON metadata |
| `service_name` | string | Storage service ("local") |
| `byte_size` | bigint | File size in bytes |
| `checksum` | string | MD5 checksum for integrity |
| `created_at` | timestamp | Record creation time |

---

## Performance Considerations

### Indexes

The wort.schule database has extensive indexing for optimal query performance:

- **Type-specific indexes**: Partial indexes on `name` for each word type (Noun, Verb, Adjective, FunctionWord)
- **Full-text search**: Trigram indexes on `meaning` and `meaning_long` for fuzzy matching
- **JSONB**: GIN index on `example_sentences` for efficient array queries
- **Composite index**: `type + name + hit_counter` for common queries

### Query Optimization Tips

1. **Always filter by type** when querying specific word types (uses partial indexes)
2. **Use preload** for associations to avoid N+1 queries
3. **Limit results** for open-ended searches (the table contains thousands of words)
4. **Use `exists?`** instead of `count` when checking for presence
5. **Cache frequent queries** in your Phoenix app (ETS or Redis)

### Connection Pooling

Since both apps share the same database, monitor connection pool usage:

```elixir
# In config
config :your_app, YourApp.WortschuleRepo,
  pool_size: 10,  # Adjust based on your needs
  queue_target: 50,
  queue_interval: 1000
```

---

## Security Notes

1. **Read-only access**: Consider creating a dedicated PostgreSQL read-only user for your Phoenix app
2. **Connection limits**: Monitor total connections to avoid exhausting PostgreSQL's `max_connections`
3. **Network access**: Ensure PostgreSQL allows connections from your Phoenix app's server
4. **Credentials**: Store database password in environment variables, never commit to version control

---

## Testing Your Integration

```elixir
# In IEx
iex> alias YourApp.Wortschule
iex> alias YourApp.WortschuleRepo, as: Repo

# Test connection
iex> Repo.query("SELECT COUNT(*) FROM words")
{:ok, %Postgrex.Result{rows: [[count]], ...}}

# Get a sample word
iex> Wortschule.get_complete_word(123)
{:ok, %{
  id: 123,
  name: "Affe",
  keywords: [%{id: 456, name: "Tier"}],
  image_url: "https://wort.schule/rails/active_storage/blobs/redirect/..."
}}
```

---

## Troubleshooting

### Connection Issues

```elixir
# Check if connection works
Repo.query("SELECT version()")

# Check if you can read words table
Repo.query("SELECT COUNT(*) FROM words")

# Verify PostgreSQL extensions
Repo.query("SELECT * FROM pg_extension WHERE extname IN ('pg_trgm', 'pgcrypto')")
```

### Common Errors

1. **Connection refused**: Check PostgreSQL `pg_hba.conf` allows connections from Phoenix server
2. **Password authentication failed**: Verify `WORTSCHULE_DATABASE_PASSWORD` environment variable
3. **Table doesn't exist**: Ensure you're connecting to the correct database
4. **Permission denied**: Create a read-only user with proper GRANT permissions

---

## Additional Resources

- [Ecto Documentation](https://hexdocs.pm/ecto)
- [PostgreSQL JSONB Queries](https://www.postgresql.org/docs/current/functions-json.html)
- [ActiveStorage URL Formats](https://edgeguides.rubyonrails.org/active_storage_overview.html)
