# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app does

**Fibr** is a garment quality analyser. A user takes 3 photos of a clothing item (label/tag, front, back), submits them, and an AI (GPT-4o via GitHub Models) scores the garment across 5 criteria: Material Quality, Stitching & Seams, Finishing, Durability, and Overall Construction. Results show a percentage score with per-criterion breakdowns.

## Development commands

```bash
# Start the server (Rails 8 + SolidQueue for background jobs)
bin/dev

# Database
bin/rails db:create db:migrate
bin/rails db:seed

# Tests
bin/rails test                          # all tests
bin/rails test test/models/user_test.rb # single test file

# Console
bin/rails console

# Security / lint
bundle exec brakeman
bundle exec rubocop
```

## Environment variables (`.env`)

| Variable | Purpose |
|---|---|
| `OPENAI_API_KEY` | GitHub Models token (used as OpenAI-compatible key) |
| `CLOUDINARY_URL` | Active Storage cloud backend |
| `VISION_SERVICE` | `"real"` → calls GPT-4o; anything else → uses `StubVisionService` |
| `GITHUB_TOKEN` | GitHub API access |

Set `VISION_SERVICE=stub` (or omit it) to skip real AI calls during development.

## Architecture

### Data model

```
User ──has_many──> Analysis ──has_one──> Chat ──has_many──> Message (has_many_attached :photos)
                      └──has_many──> Criterium
```

- `Analysis` has a status enum: `pending → processing → completed | failed`
- `Message` has a role enum: `user | assistant`
- Photos are attached to `Message` records via Active Storage (Cloudinary in production)

### Request / job flow

1. `POST /analyses` → creates `Analysis` + `Chat`, redirects to `add_pictures`
2. `GET /analyses/:id/add_pictures` → camera UI (inline JS in the view)
3. `POST /analyses/:id/messages` → attaches photos to a `user` Message, sets status to `processing`, enqueues `AnalyzeGarmentJob`
4. `AnalyzeGarmentJob` calls the vision service, writes an `assistant` Message + `Criterium` records, marks analysis `completed`
5. `GET /analyses/:id` polls `GET /analyses/:id.json` every 2 s until status leaves `processing`/`pending`, then reloads the page to show results

### Vision services (Strategy pattern)

`app/services/openai_vision_service.rb` — real AI call via `ruby-openai` gem pointed at `https://models.github.ai/inference`  
`app/services/stub_vision_service.rb` — instant fake result for local dev  
`AnalyzeGarmentJob` picks the service based on `ENV["VISION_SERVICE"] == "real"`.

### Background jobs

Rails 8 **SolidQueue** (DB-backed). `bin/dev` starts it automatically via `Procfile.dev`. No Redis needed.

### Frontend

- Bootstrap 5.3 + Font Awesome via Sprockets/Sass
- Stimulus (autoloaded from `app/javascript/controllers/`)
- The `add_pictures` view uses **inline vanilla JS** (not a Stimulus controller) to drive the camera feed, step through 3 photo captures, and manage hidden file inputs
- The `show` view uses **inline vanilla JS** for status polling (no ActionCable/Turbo Streams)

## Key files

| File | Role |
|---|---|
| `app/jobs/analyze_garment_job.rb` | Orchestrates the full AI analysis pipeline |
| `app/services/openai_vision_service.rb` | GPT-4o call + JSON parsing + prompt |
| `app/views/analyses/add_pictures.html.erb` | Camera UI + step logic (inline JS) |
| `app/views/analyses/show.html.erb` | Results display + polling loop |
| `config/routes.rb` | All routes (nested: analyses → messages) |
