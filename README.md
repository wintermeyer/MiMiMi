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
- Manual code entry form only appears when games are waiting for players (improved UX)
- Select unique animal avatar (🐻🐘🦉🐸🦊🐰🦛🐱🦁🐼)
- **Avatar Indicator**: Players see their avatar and current points in the top right corner during gameplay
- Real-time gameplay with progressive keyword reveals
- **Guaranteed Unique Words**: Each round features a different target word - no duplicate words across rounds in the same game
- Immediate feedback (correct/wrong)
- **Learning Feature**: After making a pick, all players see the correct answer with its image to reinforce learning
  - Players who picked correctly see "Du hast richtig getippt:" (You guessed correctly)
  - Players who picked wrong see "Richtige Antwort:" (Correct answer)
  - Responsive layout: side-by-side on desktop, stacked on mobile
- Live points tracking throughout the game
- Final leaderboard displayed to all players at game end

### Multiplayer Features
- Real-time updates via Phoenix PubSub
- Host dashboard showing all player activity
- Automatic round progression
- Synchronized game state across all devices
- Active games counter in footer
- **Host Disconnect Handling**: When the game host closes their browser, all players are automatically redirected to the home page with an informative flash message

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
4. **WortSchule Integration** - Full integration with wort.schule database for German word data
5. **Session Management** - Auto-create users based on session (no login required)
6. **Security** - Host authentication with cryptographic tokens (prevents waiting room hijacking)
7. **UI/UX Design** - Glassmorphism design system applied across all LiveViews
8. **LiveView Components** - Complete gameplay, dashboard, avatar selection, and lobby views
9. **Real-time Multiplayer** - Full game flow with progressive keyword reveals and synchronized state
10. **Comprehensive Testing** - Integration tests covering complete 2-3 player game scenarios

### ✅ Game is Fully Functional

The game is now complete and working correctly! Comprehensive integration tests verify:
- Two players completing a full 2-round game
- Three players with different pick speeds
- Mixed correct/wrong answers
- Points accumulation across rounds
- Proper game state transitions
- Leaderboard calculation

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

Points are awarded based on how many keywords a player needed to see before guessing correctly:

- Guess with 1 keyword shown: **5 points**
- Guess with 2 keywords shown: **3 points**
- Guess with 3 keywords shown: **1 point**
- Wrong answer: **0 points**

The faster you guess (fewer keywords needed), the more points you earn!

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

