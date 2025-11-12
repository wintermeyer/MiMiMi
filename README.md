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
- Generate unique invitation link and QR code
- 15-minute lobby timeout with countdown
- Modern glassmorphism design with smooth animations

### Player Experience
- Join via invitation link or QR code scan
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
6. **UI/UX Design** - Glassmorphism design system applied across all LiveViews

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

## 📦 Key Dependencies

- phoenix (~> 1.8.1), phoenix_live_view (~> 1.1.0)
- ecto_sql (~> 3.13), postgrex
- eqrcode (~> 0.1) for QR codes
- tailwind (~> 0.3) for styling

## 📄 Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for production deployment with hot code upgrades.

## Learn More About Phoenix

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
