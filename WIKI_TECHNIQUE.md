# 🏗️ Wiki Technique et Architecture — FIBR (Rails 8)

> **Pour qui ?** Toute l'équipe, débutante ou expérimentée. Référence unique du projet.
> **Dernière mise à jour :** 2026-06-03

---

## 1. Vision Globale et Organisation du Repository

### 1.1 Résumé du projet

FIBR est une application web Ruby on Rails 8 qui permet d'analyser la qualité de vêtements
à partir de photos. L'utilisateur photographie son vêtement (étiquette, face avant, face
arrière), soumet les images, et un service d'intelligence artificielle (GPT-4o via GitHub
Models, ou un stub de développement) retourne un score global et des critères détaillés.
Le traitement IA est asynchrone : un job SolidQueue prend en charge l'analyse en
arrière-plan pendant que l'interface affiche un spinner, puis rafraîchit automatiquement
quand c'est terminé.

### 1.2 Cartographie du Repository

| Dossier / Fichier            | Rôle dans la stack                                                                 |
|------------------------------|------------------------------------------------------------------------------------|
| `app/models/`                | Règles métier, associations, enums, validations                                    |
| `app/controllers/`           | Routage des requêtes HTTP → actions, redirections                                  |
| `app/views/`                 | Templates HTML (ERB), JS inline pour la caméra et le polling                      |
| `app/jobs/`                  | Tâches asynchrones (analyse IA) exécutées par SolidQueue                          |
| `app/services/`              | Services réutilisables : stub IA (`StubVisionService`) et vraie IA (`OpenaiVisionService`) |
| `app/javascript/`            | Turbo, Stimulus (chargement), Bootstrap — logique JS de l'UI caméra en inline     |
| `config/routes.rb`           | Déclaration de tous les endpoints HTTP de l'application                           |
| `db/schema.rb`               | Photographie de la base de données (généré automatiquement, ne pas éditer à la main) |
| `db/migrate/`                | Historique des migrations — seul moyen autorisé de modifier le schéma             |
| `Gemfile`                    | Dépendances Ruby (gems) déclarées manuellement                                    |
| `bin/dev`                    | Script de démarrage du serveur Rails (Puma)                                       |
| `bin/jobs`                   | Script de démarrage du worker SolidQueue                                          |
| `config/queue.yml`           | Configuration des files d'attente SolidQueue                                      |
| `.env`                       | Variables d'environnement locales (non versionnées)                               |

> 💡 **Analogie débutants :** Rails suit le pattern MVC. Le **Modèle** (models/) est le
> magasin de données et ses règles. La **Vue** (views/) est ce que l'utilisateur voit.
> Le **Contrôleur** (controllers/) est le chef d'orchestre qui lit la requête, parle au
> modèle, et choisit quelle vue afficher. C'est comme une commande au restaurant :
> le serveur (controller) prend votre commande, la cuisine (model) prépare le plat,
> et l'assiette servie (view) est ce que vous recevez.

---

## 2. Modèle de Données

### 2.1 L'architecture « Conversationnelle » — Pourquoi ce choix ?

Plutôt que de stocker l'analyse dans une simple table avec un champ "résultat", FIBR
modélise l'interaction comme une conversation : une `Analysis` contient un `Chat`, qui
lui-même contient des `Message`s. Cela permet d'envisager une évolution naturelle vers un
vrai chat IA (questions de suivi sur le vêtement, demande de précisions) sans refonte du
schéma. Les photos sont attachées aux `Message`s via Active Storage, ce qui est cohérent :
un message peut embarquer plusieurs pièces jointes. Les `Criterion` (plural: `criteria`)
stockent le détail du score pour chaque axe d'évaluation, séparément du score global sur
`Analysis`.

### 2.2 Schéma des tables

#### Table `users`
| Colonne                  | Type     | Contrainte   | Rôle métier                          |
|--------------------------|----------|--------------|--------------------------------------|
| `id`                     | bigint   | PK           | Identifiant unique                   |
| `email`                  | string   | NOT NULL, unique | Email de connexion (Devise)       |
| `encrypted_password`     | string   | NOT NULL     | Mot de passe hashé (Devise)          |
| `reset_password_token`   | string   | nullable, unique | Token de réinitialisation mot de passe |
| `reset_password_sent_at` | datetime | nullable     | Horodatage de l'envoi du token reset |
| `remember_created_at`    | datetime | nullable     | Gestion du "Remember me"             |
| `created_at` / `updated_at` | datetime | NOT NULL  | Timestamps automatiques Rails        |

#### Table `analyses`
| Colonne      | Type    | Contrainte   | Rôle métier                                               |
|--------------|---------|--------------|-----------------------------------------------------------|
| `id`         | bigint  | PK           | Identifiant unique                                        |
| `user_id`    | bigint  | FK, nullable | Lien vers l'utilisateur (nullable : analyse anonyme possible) |
| `status`     | integer | enum         | État du pipeline : `pending(0)` `processing(1)` `completed(2)` `failed(3)` |
| `score`      | integer | nullable     | Score global calculé par l'IA (null tant que non terminé) |
| `created_at` / `updated_at` | datetime | NOT NULL | Timestamps automatiques                  |

> ⚠️ `status` est un **enum** stocké en entier en base. Dans le code Ruby, on utilise
> `analysis.pending?`, `analysis.completed!`, etc. — Rails fait la traduction automatiquement.

#### Table `chats`
| Colonne       | Type    | Contrainte | Rôle métier                        |
|---------------|---------|------------|------------------------------------|
| `id`          | bigint  | PK         | Identifiant unique                 |
| `analysis_id` | bigint  | FK, NOT NULL | Lien vers l'analyse parente      |
| `created_at` / `updated_at` | datetime | NOT NULL | Timestamps              |

Une `Analysis` a exactement un `Chat`. C'est une relation 1-1.

#### Table `messages`
| Colonne    | Type    | Contrainte | Rôle métier                                              |
|------------|---------|------------|----------------------------------------------------------|
| `id`       | bigint  | PK         | Identifiant unique                                       |
| `chat_id`  | bigint  | FK, NOT NULL | Lien vers le chat parent                               |
| `role`     | integer | enum       | `user(0)` = photos envoyées, `assistant(1)` = réponse IA |
| `content`  | text    | nullable   | Texte du message (résumé IA pour les messages assistant) |
| `created_at` / `updated_at` | datetime | NOT NULL | Timestamps                          |

Les photos sont attachées via Active Storage (`has_many_attached :photos`).
Les tables `active_storage_attachments`, `active_storage_blobs` et
`active_storage_variant_records` sont gérées automatiquement par Rails.

#### Table `criteria`
| Colonne      | Type    | Contrainte | Rôle métier                                     |
|--------------|---------|------------|-------------------------------------------------|
| `id`         | bigint  | PK         | Identifiant unique                              |
| `analysis_id`| bigint  | FK, NOT NULL | Lien vers l'analyse parente                   |
| `name`       | string  | nullable   | Nom du critère (ex: "Material", "Cut")          |
| `detail`     | text    | nullable   | Explication courte du critère                   |
| `score`      | integer | nullable   | Score de 0 à 10 pour ce critère                |
| `created_at` / `updated_at` | datetime | NOT NULL | Timestamps                     |

> Note : le modèle Ruby s'appelle `Criterium` (singulier latin), la table SQL `criteria`.
> C'est une convention Rails pour les noms irréguliers. Dans le code, on écrit
> `analysis.criteria` pour accéder à la collection.

#### Table `profiles`
| Colonne    | Type   | Contrainte | Rôle métier                         |
|------------|--------|------------|-------------------------------------|
| `id`       | bigint | PK         | Identifiant unique                  |
| `user_id`  | bigint | FK, NOT NULL | Lien vers l'utilisateur (1-1)     |
| `created_at` / `updated_at` | datetime | NOT NULL | Timestamps           |

> La table `profiles` est structurellement présente mais ne contient pas encore de
> colonnes métier propres (pas de `first_name`, `avatar`, etc.) — elle est prête pour
> une extension future.

### 2.3 Relations entre modèles

```
User
├── has_one  :profile       (dependent: :destroy)
└── has_many :analyses      (dependent: :destroy)
    └── Analysis
        ├── belongs_to :user         (optional: true)
        ├── has_one  :chat           (dependent: :destroy)
        │   └── Chat
        │       ├── belongs_to :analysis
        │       └── has_many :messages  (dependent: :destroy)
        │           └── Message
        │               ├── belongs_to :chat
        │               └── has_many_attached :photos
        └── has_many :criteria       (dependent: :destroy, class_name: "Criterium")
            └── Criterium
                └── belongs_to :analysis
```

**Que se passe-t-il à la suppression d'un `User` ?**

Grâce aux `dependent: :destroy`, la cascade est complète :
1. Suppression du `User` → détruit son `Profile` et toutes ses `Analysis`
2. Chaque `Analysis` détruite → détruit son `Chat` et ses `Criteria`
3. Chaque `Chat` détruit → détruit tous ses `Message`s
4. Les fichiers Active Storage attachés aux `Message`s sont aussi supprimés.

**Point d'attention :** `user_id` est nullable sur `Analysis` (déclaré `optional: true`
dans le modèle). Une analyse peut donc exister sans utilisateur connecté. C'est une
décision de design intentionnelle : le contrôleur skip l'authentification pour `create`.

---

## 3. Workflow Principal (Logique Métier)

### 3.1 Flux de bout en bout — de l'upload à l'affichage

```
[1] GET /            → PagesController#home         → Page d'accueil publique
[2] POST /analyses   → AnalysesController#create    → Crée Analysis (status: pending) + Chat associé
                                                       → Redirect vers add_pictures
[3] GET /analyses/:id/add_pictures
                     → AnalysesController#add_pictures → Affiche l'interface caméra (3 photos)
[4] POST /analyses/:id/messages
                     → MessagesController#create    → Crée Message (role: user) avec photos attachées
                                                       → analysis.processing! (status → processing)
                                                       → Enfile AnalyzeGarmentJob.perform_later(analysis.id)
                                                       → Redirect vers /analyses/:id
[5] GET /analyses/:id (HTML)
                     → AnalysesController#show      → Si pending/processing : affiche spinner
                                                       → Si completed : affiche score + critères
                                                       → Si failed : affiche message d'erreur
[6] POLLING toutes 2s : GET /analyses/:id (JSON)
                     → AnalysesController#show      → Répond { status: "pending"|"processing"|"completed"|"failed" }
                                                       → Quand status != pending/processing : window.location.reload()
[7] Côté worker (asynchrone) :
                     → AnalyzeGarmentJob#perform    → Appelle StubVisionService (ou OpenaiVisionService)
                                                       → Crée Message (role: assistant) avec le résumé IA
                                                       → Crée les Criteria (3 à 5 selon le service)
                                                       → Met à jour analysis.score
                                                       → analysis.completed! (ou failed! en cas d'erreur)
[8] Le polling détecte status != pending/processing → reload → [5] affiche les résultats
```

### 3.2 Rôle de chaque Controller

#### `ApplicationController`
- Applique `before_action :authenticate_user!` sur **toutes** les actions par défaut.
- Les controllers enfants peuvent lever cette restriction avec `skip_before_action`.

#### `PagesController`
| Action | Responsabilité | Output HTTP |
|--------|----------------|-------------|
| `home` | Page d'accueil publique (skip authenticate) | `200 OK` — `pages/home.html.erb` |

#### `AnalysesController`
| Action        | Responsabilité | Output HTTP |
|---------------|----------------|-------------|
| `create`      | Crée une nouvelle `Analysis` + son `Chat` | `302` → `add_pictures` |
| `add_pictures`| Prépare l'interface de capture photo | `200 OK` — `analyses/add_pictures.html.erb` |
| `show`        | Affiche les résultats ou le spinner ; répond JSON pour le polling | `200 OK` HTML ou JSON |

> `skip_before_action :authenticate_user!, only: [:create, :add_pictures, :show]` :
> ces trois actions sont publiques, l'analyse fonctionne même sans compte.

#### `MessagesController`
| Action   | Responsabilité | Output HTTP |
|----------|----------------|-------------|
| `create` | Attache les photos, passe l'analyse en `processing`, enfile le job | `302` → `analysis_path` |

> `skip_before_action :authenticate_user!` sans restriction `only:` : **toutes** les
> actions de ce controller sont publiques.

---

## 4. Jobs Asynchrones et « Stub » IA (SolidQueue)

### 4.1 Pourquoi traiter l'analyse en arrière-plan ?

Analyser des images avec une IA peut prendre plusieurs secondes (ou dizaines de secondes).
Si on faisait cette opération dans la requête HTTP directement, le navigateur resterait
bloqué à attendre, et le serveur web ne pourrait pas traiter d'autres requêtes en attendant.

**Analogie restaurant :** le serveur (Rails) prend votre commande, l'envoie en cuisine
(le job), et revient immédiatement vous servir d'autres tables. Quand le plat est prêt,
le client est notifié (via le polling). Personne n'attend debout devant les fourneaux.

### 4.2 Comment fonctionne `AnalyzeGarmentJob` ?

**Fichier :** `app/jobs/analyze_garment_job.rb`

**Cycle de vie :**

```
MessagesController#create
  │
  ├─► analysis.processing!            # Status → processing
  └─► AnalyzeGarmentJob.perform_later(analysis.id)  # Enfiler dans SolidQueue
                │
                │  (quelques instants plus tard, dans le worker)
                ▼
         AnalyzeGarmentJob#perform(analysis_id)
           │
           ├─► Choisit le service selon ENV["VISION_SERVICE"]
           │     "real" → OpenaiVisionService
           │     autre  → StubVisionService (défaut)
           │
           ├─► service.call  →  { content:, score:, criteria: [...] }
           │
           ├─► chat.messages.create!(role: :assistant, content: result[:content])
           ├─► result[:criteria].each { analysis.criteria.create!(attrs) }
           ├─► analysis.update!(score: result[:score])
           └─► analysis.completed!
                │
                └─► En cas d'erreur StandardError : analysis.failed!
```

**Commande pour lancer le worker en local :**
```bash
bin/jobs start
```

> ⚠️ **Sans worker lancé, les analyses restent éternellement en statut `processing`.**
> Le spinner tournera sans fin car aucun job ne sera traité.

**File d'attente :** `:default` — configurée dans `config/queue.yml`.

**Gestion des erreurs :**
- `ActiveRecord::RecordNotFound` : log d'erreur, le job s'arrête proprement (l'analyse n'existe plus).
- Toute autre `StandardError` : `analysis.failed!` + log d'erreur.

### 4.3 Le concept de « Stub » IA — rien n'est payant

`StubVisionService` (`app/services/stub_vision_service.rb`) est un faux service IA qui
retourne toujours le même résultat fictif après un délai simulé de 2 secondes.

```ruby
def call
  sleep 2  # simule le "temps de réflexion" de l'IA
  {
    content: "Simulated analysis: good quality fabric...",
    score: 8,
    criteria: [
      { name: "Material", detail: "...", score: 8 },
      { name: "Cut",      detail: "...", score: 7 },
      { name: "Finishing",detail: "...", score: 9 }
    ]
  }
end
```

**C'est une technique standard de développement.** Elle permet de :
- Travailler sur l'UI et le flux complet sans clé API ni coût
- Tester le pipeline bout en bout (upload → job → résultat) instantanément
- Éviter les quotas et la latence réseau pendant le développement

La variable d'environnement `VISION_SERVICE=real` dans `.env` bascule vers le vrai service.

### 4.4 Brancher la vraie IA plus tard

Le vrai service existe déjà : `app/services/openai_vision_service.rb` utilise la gem
`ruby-openai` avec le modèle `openai/gpt-4o` via l'endpoint GitHub Models
(`https://models.github.ai/inference`). Pour l'activer :

1. Définir `OPENAI_API_KEY` dans `.env` (token GitHub Models ou OpenAI)
2. Définir `VISION_SERVICE=real` dans `.env`
3. Le job bascule automatiquement vers `OpenaiVisionService`

Le service encode les photos en base64, construit un message multimodal (texte + images),
attend une réponse JSON structurée de l'IA, puis la parse pour alimenter les `Criterion`.
Le prompt système force une réponse JSON pure sans texte parasite (important pour le
parsing).

---

## 5. Blueprint pour l'intégration future de Turbo/Hotwire

### 5.1 Post-mortem de l'implémentation annulée

Une première tentative d'intégration Turbo/Stimulus a été annulée (revert) à cause de
deux familles de bugs :

1. **Boucles infinies de rechargement** : un controller Stimulus modifiait un attribut
   de l'élément (typiquement `src` ou un attribut `data-` surveillé par Turbo), ce qui
   déclenchait un rechargement Turbo, qui réinitialisait le controller Stimulus, qui
   re-modifiait l'attribut, etc.

2. **Rechargements incontrôlés** : des `setInterval` ou observateurs n'étaient pas
   nettoyés lors de la déconnexion du controller, causant des timers fantômes qui
   continuaient à tourner après navigation.

**Ce qu'on en apprend :** Turbo et Stimulus ont des cycles de vie précis. Un controller
Stimulus doit être **stateless** entre les reconnexions et gérer rigoureusement son
propre nettoyage. La solution actuelle (polling en JS vanilla inline dans la vue) est
plus robuste pour l'instant, même si moins élégante.

### 5.2 Les règles d'or pour ne pas reproduire ces bugs

> ⚠️ **Règle n°1 — Ne jamais modifier `this.element.src` (ou un attribut observé par Turbo)
> dans un controller Stimulus pour déclencher un refresh.**
> Boucle infinie garantie : Turbo charge la frame → Stimulus s'initialise → `connect()`
> modifie `src` → Turbo recharge la frame → Stimulus se réinitialise → etc.

> ⚠️ **Règle n°2 — Toujours nettoyer les timers dans `disconnect()`.**
> `setInterval` et `setTimeout` survivent à la destruction du controller si on ne les
> arrête pas. `disconnect()` est appelé à chaque navigation Turbo — c'est votre
> destructeur, utilisez-le.

> ⚠️ **Règle n°3 — Démarrer le polling uniquement si nécessaire.**
> Dans `connect()`, vérifier d'abord le statut initial (via un `data-` attribute ou
> un fetch léger). Ne lancer le timer que si `status === 'pending'` ou `'processing'`.
> Si la page se charge avec `status === 'completed'`, il ne faut rien démarrer.

> ⚠️ **Règle n°4 — Séparer l'endpoint de polling de la vue principale.**
> Le polling doit appeler un endpoint JSON léger (`GET /analyses/:id/status`) qui
> retourne uniquement `{ status: "..." }`, **pas** la page entière. Évite de recharger
> le DOM complet à chaque tick et simplifie la logique.

> ⚠️ **Règle n°5 — Ne jamais appeler `window.location.reload()` depuis Stimulus.**
> Utiliser Turbo pour mettre à jour le DOM (`Turbo.visit()` ou un Turbo Stream).
> `window.location.reload()` est acceptable en JS vanilla (comme dans la vue actuelle),
> mais dans un controller Stimulus lié à une Turbo Frame, cela peut créer des conflits.

### 5.3 Architecture cible recommandée

#### Turbo Frames — encapsuler des fragments

**Zone de résultats** (`analyses/show.html.erb`) : encapsuler le bloc conditionnel
(spinner OU résultats OU erreur) dans une `<turbo-frame id="analysis-result">`.
Cela permettra de mettre à jour uniquement ce fragment sans recharger la page entière.

```erb
<turbo-frame id="analysis-result">
  <%# ... le contenu conditionnel actuel ... %>
</turbo-frame>
```

**Zone de statut** dans `add_pictures` : les indicateurs PENDING/OK (tag/front/back)
pourraient rester en JS vanilla car ils répondent à des événements locaux (capture
caméra), pas à des données serveur.

#### Turbo Streams — mises à jour serveur → client

Quand `AnalyzeGarmentJob` termine, il peut broadcaster un Turbo Stream pour remplacer
la frame `analysis-result` sans que le client ait besoin de poller :

```ruby
# Dans AnalyzeGarmentJob#perform, après analysis.completed!
Turbo::StreamsChannel.broadcast_replace_to(
  "analysis_#{analysis.id}",
  target: "analysis-result",
  partial: "analyses/result",
  locals: { analysis: analysis }
)
```

**Le polling actuel vs Turbo Streams :**
- Le polling (solution actuelle) est simple, robuste, fonctionne partout.
- Turbo Streams est plus élégant et réactif, mais nécessite Action Cable (WebSockets)
  configuré avec `solid_cable` (déjà présent dans le Gemfile).

#### Stimulus — pattern de polling correct

Si on garde le polling côté client tout en adoptant Stimulus, voici le pattern à suivre :

```javascript
// app/javascript/controllers/analysis_status_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // data-analysis-status-url-value = "/analyses/42/status" (JSON endpoint)
  static values = { url: String, status: String }

  connect() {
    // Ne démarre le timer QUE si l'analyse est encore en cours
    if (this.statusValue === "pending" || this.statusValue === "processing") {
      this.startPolling()
    }
  }

  disconnect() {
    // TOUJOURS arrêter le timer — appelé à chaque navigation Turbo
    this.stopPolling()
  }

  startPolling() {
    this.timer = setInterval(() => this.fetchStatus(), 2000)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  fetchStatus() {
    fetch(this.urlValue, { headers: { "Accept": "application/json" } })
      .then(r => r.json())
      .then(data => {
        if (data.status !== "pending" && data.status !== "processing") {
          this.stopPolling()
          // Laisser Turbo mettre à jour le DOM — NE PAS appeler window.location.reload()
          Turbo.visit(window.location.href)
        }
      })
      .catch(() => this.stopPolling())
  }
}
```

Usage dans la vue :
```erb
<div data-controller="analysis-status"
     data-analysis-status-url-value="<%= analysis_path(@analysis, format: :json) %>"
     data-analysis-status-status-value="<%= @analysis.status %>">
  <%# ... spinner ... %>
</div>
```

### 5.4 Endpoint JSON recommandé pour le polling

L'action `show` répond déjà au format JSON (`format.json { render json: { status: @analysis.status } }`).
Pour une architecture plus propre, on pourrait dédier un endpoint :

```
GET /analyses/:id/status → { "status": "pending" | "processing" | "completed" | "failed" }
```

**Avantages :**
- URL explicite et sémantique (bookmarkable, loggable)
- Séparation claire entre la ressource principale et son état courant
- Léger (pas de rendu de vue, juste un JSON minimaliste)

**Implémentation dans le controller :**
```ruby
# config/routes.rb
resources :analyses, only: [:create, :show] do
  get :status, on: :member   # → GET /analyses/:id/status
  get :add_pictures, on: :member
  resources :messages, only: [:create]
end
```

---

## 6. Guide de Survie et Maintenance

### 6.1 Lancer l'application en local

> ⚠️ Il n'y a **pas** de `Procfile.dev` dans ce projet. `bin/dev` lance uniquement
> le serveur Rails (Puma). Le worker SolidQueue doit être lancé séparément.

**Terminal 1 — Serveur Rails :**
```bash
bin/dev
# équivalent à : bin/rails server
# Accessible sur http://localhost:3000
```

**Terminal 2 — Worker SolidQueue :**
```bash
bin/jobs start
# Lance SolidQueue::Cli — traite les jobs en file d'attente :default
```

> ⚠️ **Sans le terminal 2, les analyses resteront éternellement en `processing`.**
> Le spinner tournera sans fin car personne ne traite les jobs.

**Variable d'environnement pour la vraie IA :**
```bash
# Dans .env (non versionné)
OPENAI_API_KEY=votre_token_github_models
VISION_SERVICE=real
```
Sans ces variables, le stub (`StubVisionService`) est utilisé automatiquement.

### 6.2 Commandes utiles au quotidien

| Commande | Description |
|----------|-------------|
| `bin/rails server` | Démarre le serveur web Puma |
| `bin/jobs start` | Démarre le worker SolidQueue |
| `bin/rails db:migrate` | Applique les migrations en attente |
| `bin/rails db:rollback` | Annule la dernière migration |
| `bin/rails db:schema:load` | Recrée la base depuis schema.rb (dev seulement) |
| `bin/rails console` | Console interactive (REPL) — tester des requêtes Ruby/ActiveRecord |
| `bin/rails routes` | Lister toutes les routes avec leur nom, méthode HTTP et controller |
| `bin/rails routes \| grep analyse` | Filtrer les routes liées aux analyses |
| `bin/rails test` | Lancer la suite de tests |
| `bin/rails test test/models/analysis_test.rb` | Lancer un fichier de test spécifique |
| `bin/brakeman` | Audit de sécurité statique (cherche les vulnérabilités Rails) |
| `bin/bundler-audit` | Audit des gems pour des CVE connues |

### 6.3 Bonnes pratiques de l'équipe

1. **Jamais éditer `db/schema.rb` à la main.** Ce fichier est généré automatiquement
   par `rails db:migrate`. Toute modification du schéma passe par une migration
   (`rails generate migration NomDeLaMigration`).

2. **Tester le job en console avant de toucher aux vues.** Avant d'intégrer une
   nouvelle fonctionnalité dans l'UI, vérifier que le job se comporte correctement :
   ```ruby
   # Dans bin/rails console
   analysis = Analysis.last
   AnalyzeGarmentJob.perform_now(analysis.id)
   analysis.reload.status   # → "completed" ?
   analysis.criteria.count  # → 3 ?
   ```

3. **Pas de `binding.pry` ni `byebug` oublié en commit.** Ces instructions de débogage
   bloquent le serveur en production. Le linter rubocop devrait les signaler, mais
   vérifier manuellement avant tout `git commit`.

4. **Utiliser le stub en développement, la vraie IA uniquement pour les tests d'intégration.**
   Cela évite de consommer du quota API pour du développement quotidien.

5. **Le controller skip l'authentification pour les analyses.** C'est intentionnel.
   Si on ajoute une action protégée à `AnalysesController`, ne pas oublier de la
   retirer de la liste `skip_before_action`.

6. **Active Storage + Cloudinary.** La gem `cloudinary` est dans le Gemfile.
   La configuration du service de stockage (local vs Cloudinary) se fait dans
   `config/storage.yml` et `config/environments/*.rb`.

---

## 7. Glossaire — Termes Clés

| Terme | Définition simple |
|-------|-------------------|
| **SolidQueue** | File d'attente de jobs intégrée à Rails 8, stockée en base de données PostgreSQL. Pas besoin de Redis ni d'un service externe. Les jobs s'y enfilent et le worker (`bin/jobs start`) les traite. |
| **Job** | Tâche de fond qui s'exécute en dehors du cycle requête/réponse HTTP. `AnalyzeGarmentJob` analyse les photos de façon asynchrone. |
| **Stub** | Faux service qui imite le comportement d'un vrai service (ici l'IA) sans l'appeler réellement. Utilisé en développement pour travailler sans clé API ni coût. `StubVisionService` est le stub de FIBR. |
| **Enum** | Type Rails qui mappe des entiers en base de données vers des noms symboliques dans le code. `Analysis.status` : `0=pending`, `1=processing`, `2=completed`, `3=failed`. Permet d'écrire `analysis.completed?` plutôt que `analysis.status == 2`. |
| **Active Storage** | Module Rails pour gérer les fichiers attachés (photos, PDFs…). Dans FIBR, les photos de vêtements sont attachées aux `Message`s. |
| **Turbo Frame** | Balise HTML `<turbo-frame>` qui isole une portion de page. Quand Turbo navigue vers une URL, il ne remplace que le contenu de la frame correspondante, sans recharger toute la page. |
| **Turbo Stream** | Mécanisme Turbo qui permet au serveur d'envoyer des instructions de mise à jour DOM (append, replace, remove…) en temps réel, typiquement depuis un job via Action Cable. |
| **Stimulus** | Framework JavaScript minimaliste de Hotwire. On écrit des « controllers » qui s'attachent à des éléments HTML via `data-controller`. Dans FIBR après le revert, seul le controller de démonstration `hello_controller.js` reste actif. |
| **MVC** | Model-View-Controller. Pattern d'architecture de Rails : le Modèle gère les données, la Vue affiche, le Controller reçoit les requêtes et coordonne. |
| **`dependent: :destroy`** | Option d'association ActiveRecord qui détruit automatiquement les enregistrements associés quand l'enregistrement parent est supprimé. Évite les données orphelines en base. |
| **Devise** | Gem d'authentification complète pour Rails (inscription, connexion, mot de passe oublié, "remember me"). Génère les routes `devise_for :users` et les vues dans `app/views/devise/`. |
| **Polling** | Technique où le client interroge le serveur à intervalles réguliers pour connaître l'état d'une opération. Dans FIBR, la vue `show` fait un `fetch` JSON toutes les 2 secondes jusqu'à ce que l'analyse soit terminée. |
| **Active Job** | Couche d'abstraction Rails pour les jobs asynchrones. `AnalyzeGarmentJob` hérite de `ApplicationJob < ActiveJob::Base`. SolidQueue est l'adaptateur (backend) qui exécute ces jobs. |
| **`optional: true`** | Modificateur `belongs_to` qui permet à la clé étrangère d'être `nil`. Sans ça, Rails validerait la présence de `user_id` à chaque save. Dans FIBR, une `Analysis` peut être créée sans utilisateur connecté. |
| **Cloudinary** | Service cloud de gestion d'images (CDN, transformations). La gem est présente dans le Gemfile ; la configuration `config/storage.yml` détermine si Active Storage envoie les fichiers vers Cloudinary ou les stocke localement. |
| **GitHub Models** | API compatible OpenAI proposée par GitHub pour accéder à des modèles IA (dont GPT-4o). Utilisée par `OpenaiVisionService` via `uri_base: "https://models.github.ai/inference"`. |
