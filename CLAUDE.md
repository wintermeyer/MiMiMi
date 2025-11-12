# In ./CLAUDE.md
@AGENTS.md
- This is a mobile first application.
- Always create a normal and a dark mode variant (e.g. dark:test-white).
- Always use vanilla TailwindCSS. Don't introduce extra CSS.
- The UX is in German. The documentation in English.
- Only push to GitHub when I tell you so.

## Design System - Glassmorphism

All LiveViews in this application follow a consistent **glassmorphism design language**. Always apply these principles when creating or updating any UI component.

### Core Design Principles

#### 1. Background Gradients
- **Light mode**: `bg-gradient-to-b from-indigo-50 to-white`
- **Dark mode**: `dark:from-gray-950 dark:to-gray-900`
- Apply to the outermost container div with `min-h-screen`

#### 2. Glassmorphism Cards
All major content containers must use glassmorphism styling:
```
backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50
```

Key elements:
- `backdrop-blur-xl` - Creates the frosted glass effect
- `bg-white/70` - 70% opacity white background (light mode)
- `dark:bg-gray-800/70` - 70% opacity dark background (dark mode)
- `rounded-3xl` - Large rounded corners for modern look
- `shadow-2xl` - Prominent shadow for depth
- Semi-transparent borders with 50% opacity

#### 3. Gradient Icon Badges
Use circular gradient badges for page icons:
```heex
<div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 mb-4 shadow-lg">
  <span class="text-4xl">🎮</span>
</div>
```

**Color gradients by context:**
- Purple → Pink: Primary actions, game setup
- Blue → Cyan: Waiting/loading states
- Green → Emerald: Success, avatar selection
- Yellow → Orange: Winners, completion
- Orange → Red: Active gameplay

#### 4. Input Fields & Form Elements
All inputs must have:
- Clean white/dark backgrounds with 2px borders
- Hover effects with subtle gradient overlays (opacity 0 → 0.1)
- Focus states with colored borders and ring effects
- Rounded corners (`rounded-xl` or `rounded-2xl`)

Example structure:
```heex
<div class="relative group">
  <div class="absolute inset-0 bg-gradient-to-r from-purple-500 to-pink-500 rounded-xl opacity-0 group-hover:opacity-10 transition-opacity duration-300"></div>
  <input class="relative w-full px-4 py-3.5 bg-white dark:bg-gray-900 border-2 border-gray-200 dark:border-gray-700 rounded-xl focus:border-purple-500 dark:focus:border-purple-400 focus:ring-4 focus:ring-purple-100 dark:focus:ring-purple-900/30 transition-all duration-200 dark:text-white outline-none" />
</div>
```

#### 5. Buttons

**Primary Action Buttons:**
```heex
<button class="relative w-full py-4 bg-gradient-to-r from-purple-600 via-purple-500 to-pink-500 hover:from-purple-700 hover:via-purple-600 hover:to-pink-600 text-white rounded-2xl shadow-xl shadow-purple-500/30 hover:shadow-2xl hover:shadow-purple-500/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 font-semibold overflow-hidden group">
  <div class="absolute inset-0 bg-gradient-to-r from-white/0 via-white/20 to-white/0 translate-x-[-100%] group-hover:translate-x-[100%] transition-transform duration-700"></div>
  <span class="relative">Button Text</span>
</button>
```

Key features:
- Gradient backgrounds with color-matched shadows
- Shimmer effect on hover (light sweep animation)
- Scale animations (1.02 on hover, 0.98 on active)
- Always use `overflow-hidden` with `group` for shimmer effect

**Grid Selection Buttons:**
Use different gradient colors for each option to help users distinguish choices visually.

**Success Buttons (e.g., "Start Game"):**
```
bg-gradient-to-r from-green-500 to-emerald-500
```

#### 6. Typography
- **Headings**: `text-4xl font-bold text-gray-900 dark:text-white`
- **Subheadings**: `text-lg font-semibold text-gray-900 dark:text-white`
- **Body text**: `text-gray-600 dark:text-gray-400`
- **Accent text**: `text-purple-600 dark:text-purple-400`

#### 7. Hover States & Micro-interactions
All interactive elements must have:
- Smooth transitions (`transition-all duration-200` or `duration-300`)
- Gradient overlays on hover (opacity 0 → 10%)
- Subtle scale effects on buttons (`hover:scale-[1.02]`)
- Color-matched shadows that intensify on hover

#### 8. Spacing & Layout
- Main content containers: `max-w-md` to `max-w-4xl` depending on content
- Padding for cards: `p-6` or `p-8`
- Margin between sections: `mb-6` to `mb-10`
- Consistent `px-4 py-12` for page-level padding

#### 9. Empty States
Always include friendly empty states with:
- Large emoji icon (text-6xl)
- Descriptive text
- Centered layout
```heex
<div class="text-center py-8">
  <div class="text-6xl mb-4 opacity-50">👥</div>
  <p class="text-gray-600 dark:text-gray-400">Warte auf Spieler...</p>
</div>
```

#### 10. Grid Layouts for Avatars/Players
Use consistent grid layouts:
- Mobile: `grid-cols-2` or `grid-cols-3`
- Tablet: `sm:grid-cols-4`
- Desktop: `md:grid-cols-5` or `md:grid-cols-6`
- Gap: `gap-3` or `gap-4`
- All items in grids should have `aspect-square` for uniform sizing

### Common Patterns

#### Header with Icon Badge
```heex
<div class="text-center mb-10">
  <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 mb-4 shadow-lg">
    <span class="text-4xl">🎮</span>
  </div>
  <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-2">
    Page Title
  </h1>
  <p class="text-gray-500 dark:text-gray-400 text-sm">
    Subtitle text
  </p>
</div>
```

#### Card with Hover Effect Items
```heex
<div class="backdrop-blur-xl bg-white/70 dark:bg-gray-800/70 rounded-3xl p-8 shadow-2xl border border-gray-200/50 dark:border-gray-700/50">
  <div class="grid grid-cols-3 gap-3">
    <div class="relative ... overflow-hidden group">
      <div class="absolute inset-0 bg-gradient-to-br from-purple-500 to-pink-500 opacity-0 group-hover:opacity-10 transition-opacity duration-300"></div>
      <span class="relative">Content</span>
    </div>
  </div>
</div>
```

### Do's and Don'ts

**DO:**
- Always use glassmorphism cards for main content areas
- Include gradient icon badges at the top of pages
- Use subtle gradient overlays on hover (10% opacity max)
- Apply smooth transitions to all interactive elements
- Use colored shadows that match gradient colors
- Maintain consistent spacing and rounded corners

**DON'T:**
- Don't use sharp corners or harsh borders
- Don't use solid backgrounds without the glassmorphism effect
- Don't skip dark mode variants
- Don't use emojis in text unless explicitly for icons
- Don't mix design styles (stay consistent with glassmorphism)
- Don't use `opacity-100` for backgrounds (use 70% for glass effect)

### Testing Checklist
When creating or updating a LiveView, verify:
- [ ] Background gradient applied to page container
- [ ] All major content in glassmorphism cards
- [ ] Gradient icon badge included in header
- [ ] All buttons have hover states and animations
- [ ] Dark mode fully implemented and tested
- [ ] Responsive on mobile, tablet, and desktop
- [ ] Empty states are user-friendly
- [ ] Consistent spacing throughout
- [ ] Smooth transitions on all interactions
