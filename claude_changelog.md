# Claude Changelog — FIBR MVP (flux métier bout en bout)

## Fichiers modifiés

- **`config/routes.rb`** — Déjà correct (root, analyses, messages imbriqués). Aucune modification nécessaire.

- **`app/models/analysis.rb`** — Déjà correct : `belongs_to :user (optional)`, `has_one :chat`, `has_many :criteria`, `enum :status` avec default `:pending`. Aucune modification.

- **`app/models/chat.rb`** — Déjà correct : `belongs_to :analysis`, `has_many :messages dependent: :destroy`. Aucune modification.

- **`app/models/message.rb`** — Déjà correct : `belongs_to :chat`, `has_many_attached :photos`, `enum :role` avec default `:user`. Aucune modification.

- **`app/models/criterium.rb`** — Déjà correct : `belongs_to :analysis`. Aucune modification.

- **`app/models/user.rb`** — Déjà correct : Devise, `has_one :profile`, `has_many :analyses`. Aucune modification.

- **`app/models/profile.rb`** — Déjà correct : `belongs_to :user`. Aucune modification.

- **`app/controllers/analyses_controller.rb`** *(modifié)* — Suppression du bloc `respond_to / format.json` dans `show` (rendu HTML classique uniquement). Ajout de commentaires en français sur chaque action.

- **`app/controllers/messages_controller.rb`** *(modifié)* — Ajout de commentaires en français expliquant chaque étape (récupération de l'analyse, attachement des photos, passage en `processing`, enfilage du job, redirection).

- **`app/jobs/analyze_garment_job.rb`** *(modifié)* — Ajout de commentaires en français détaillant chaque étape du stub IA (sleep, création du message assistant, création des critères, passage en `completed`, gestion des erreurs).

- **`app/views/analyses/add_pictures.html.erb`** — Déjà correct : formulaire Bootstrap avec `file_field :photos, multiple: true`. Aucune modification.

- **`app/views/analyses/show.html.erb`** *(modifié — changement principal)* — Remplacement du bloc `<script>` de polling JavaScript par :
  - Un `content_for :head` injectant `<meta http-equiv="refresh" content="3">` dans le `<head>` du layout uniquement si `pending?` ou `processing?`.
  - Un `turbo_frame_tag @analysis` enveloppant toute la zone conditionnelle (spinner / résultats / erreur).
  - Aucun JavaScript dans la vue. Aucun Turbo Stream. Aucun ActionCable.

- **`app/views/pages/home.html.erb`** — Déjà correct : bouton "Commencer l'analyse" pointant vers `analyses_path` (POST). Aucune modification.

- **`claude_changelog.md`** *(créé)* — Ce fichier.

---

## Confirmation Stub IA

- **Stub IA implémenté : OUI**
- **Appel API OpenAI ou service externe présent : NON**
- Le job `AnalyzeGarmentJob` utilise exclusivement des données statiques (`STUB_CRITERIA`) et un `sleep 2` pour simuler le traitement.

---

## Problèmes et limitations rencontrés

- **`<meta http-equiv="refresh">` et Turbo Frames** : la balise meta est injectée dans le `<head>` via `content_for :head` (déjà prévu dans `layouts/application.html.erb` avec `yield :head`). Cela provoque un rechargement natif du navigateur toutes les 3 secondes. Turbo intercepte ce rechargement et met à jour le frame correspondant. C'est le comportement attendu et conforme aux contraintes (pas de Redis, pas de WebSocket).

- **Table `criteria` vs classe `Criterium`** : Rails génère le modèle `Criterium` pour la table `criteria`. La relation dans `Analysis` utilise `class_name: "Criterium"` pour que `@analysis.criteria` fonctionne avec le nom Rails-standard. Cela était déjà en place avant l'intervention.

- **Analyses sans utilisateur** : `belongs_to :user, optional: true` et `skip_before_action :authenticate_user!` permettent de créer une analyse sans être connecté (MVP sans authentification obligatoire). À restreindre si l'authentification devient obligatoire.

- **SolidQueue** : pour que `AnalyzeGarmentJob` s'exécute, le worker SolidQueue doit tourner (`bin/jobs` ou équivalent). En développement, penser à lancer `bin/jobs` dans un second terminal.
