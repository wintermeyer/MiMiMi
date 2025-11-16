# MiMiMi - Multiplayer Word Guessing Game for Kids

A mobile-first multiplayer word-guessing game built with Phoenix LiveView for German elementary school students (Grundschüler). Players see a grid of words/images and must guess the correct word based on progressively revealed keywords (clues).

## 🎮 Game Overview

**Target Audience:** German elementary school students
**Language:** German (einfache Sprache - simple language for children)
**Platform:** Web-based, mobile-first design
**Technology:** Phoenix LiveView with real-time multiplayer features

## ✨ Features

### Game Setup (Host/Teacher)
- Configure number of rounds (1-20, default: 3)
- Set clue reveal interval (3s to 60s)
- Choose grid size (2x1, 2x2, 3x3, or 4x4)
- Generate unique 6-digit invitation code (expires after 15 minutes)
- Large, prominent display of invitation code in dashboard for easy reading
- Share code via QR code, link, or direct code entry
- 15-minute lobby timeout with countdown
- Secure host authentication with cryptographic tokens
- Modern glassmorphism design with smooth animations

### Player Experience
- Join via invitation link, QR code scan, or manual 6-digit code entry
- Manual code entry on home page for easy joining without links
- Select unique animal avatar (🐻🐘🦉🐸🦊🐰🦛🐱🦁🐼)
- Real-time gameplay with progressive keyword reveals
- Immediate feedback (correct/wrong)
- Live leaderboard with points

### Multiplayer Features
- Real-time updates via Phoenix PubSub
- Host dashboard showing all player activity
- Automatic round progression
- Synchronized game state across all devices
- Active games counter in footer

### Word List Page
- Browse all words from WortSchule database that have keywords and images
- Visit `/list_words` to see the complete word collection with visuals
- Each word displays its image and all associated keywords
- Filter words by minimum number of keywords using the interactive slider
- Slider range dynamically adjusts to the maximum keyword count in the database
- Filtering correctly excludes orphaned keywords (keywords pointing to non-existent words)
- Images are loaded directly from wort.schule with complete URLs

### Debug Page
- System diagnostics at `/debug` (excluded from search engines via robots.txt)
- Displays Elixir version, Phoenix version, app version, and build timestamp
- Shows WortSchule database connection status
- Reports table counts for all WortSchule tables:
  - Total words, words with images, words with keywords
  - Words with both keywords and images (usable in game)
  - Keywords, ActiveStorage attachments and blobs
- Error handling with detailed error messages for troubleshooting

## 🎨 Design System

The application uses a modern **glassmorphism design language** with:
- Frosted glass card effects with backdrop blur
- Soft gradient backgrounds (indigo → white)
- Smooth transitions and micro-interactions
- Context-specific gradient icon badges
- Color-matched shadows on interactive elements
- Full dark mode support

See `CLAUDE.md` for complete design system documentation.

## 🏗️ Implementation Status

### ✅ Completed

1. **Database Layer** - All 7 tables migrated with proper indexes and foreign keys
2. **Ecto Schemas** - User, Game, Player, Word, Keyword, Round, Pick
3. **Context Layer** - Complete Games context with all CRUD operations and PubSub
4. **Seed Data** - 65+ German words across 8 categories in einfache Sprache
5. **Session Management** - Auto-create users based on session (no login required)
6. **Security** - Host authentication with cryptographic tokens (prevents waiting room hijacking)
7. **UI/UX Design** - Glassmorphism design system applied across all LiveViews

### 🚧 In Progress

LiveView modules, routing, UI components, and game flow logic are next in the implementation queue.

## 🚀 Getting Started

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.setup

# Start Phoenix server
mix phx.server
```

Visit `http://localhost:4000`

## 📊 Scoring System

**Formula:** `points = total_keywords - keywords_shown + 1`

- Guess with 1 keyword shown: 5 points
- Guess with 3 keywords shown: 3 points
- Wrong answer: 0 points

## 🔒 Security

### Host Authentication
- Each game generates a unique cryptographic host token (32-byte secure random)
- Host token stored in signed session cookie (expires after 24 hours)
- Waiting room access requires valid host token matching the game's stored token
- Prevents unauthorized users from hijacking the waiting room and starting games
- Even with the same URL, attackers cannot impersonate the game host without the valid token

## 🔗 WortSchule Integration

This application integrates with the [wort.schule](https://wort.schule) database for accessing German word data, keywords, and images.

### Configuration

The app uses a dedicated read-only repository (`Mimimi.WortSchuleRepo`) for accessing the external wort.schule database:

**Development:**
- Database: `wortschule_development`
- Same PostgreSQL credentials as main app

**Production:**
- Database: `wortschule_production`
- Username: `wortschule`
- Password: Set via `WORTSCHULE_DATABASE_PASSWORD` environment variable
- Host: `localhost` (configurable via `WORTSCHULE_DATABASE_HOST`)

### Usage

```elixir
# Get a complete word with keywords and image URL
{:ok, word} = Mimimi.WortSchule.get_complete_word(123)
# => %{id: 123, name: "Affe", keywords: [...], image_url: "https://..."}

# Search words
words = Mimimi.WortSchule.search_words("Tier")

# List words with filters
words = Mimimi.WortSchule.list_words(type: "Noun", limit: 10)

# Get image URL (cached for 24 hours)
url = Mimimi.WortSchule.get_image_url(word_id)
```

### Image URL Cache

The application uses an in-memory ETS cache for WortSchule image URLs to minimize API calls:

- **Cache Duration**: 24 hours
- **Storage**: In-memory ETS table (no database overhead)
- **Auto-cleanup**: Expired entries are removed every 6 hours
- **Benefits**: Significantly reduces API calls and improves performance

Cache management:
```elixir
# View cache statistics
Mimimi.WortSchule.ImageUrlCache.stats()
# => %{total: 150, expired: 5, active: 145}

# Clear cache (if needed)
Mimimi.WortSchule.ImageUrlCache.clear()
```

### Direct Image URLs

The wort.schule JSON API now provides complete, direct image URLs without redirects. All image URLs returned by `Mimimi.WortSchule.get_image_url/1` and `get_complete_word/1` are direct URLs from wort.schule (e.g., `https://wort.schule/rails/active_storage/disk/...`).

See `WortSchuleIntegration.md` for complete integration documentation.

## 📄 Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for production deployment with hot code upgrades.

