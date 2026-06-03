# Audit de sécurité & qualité — Fibr (Rails 8.1.3)

> Date : 2026-06-02
> Auditeur : Claude Sonnet 4.6

---

## 1. Bugs et correctness

---

**🔴 Critique — `app/controllers/analyses_controller.rb:6-7` — Absence de transaction entre `save!` et `create_chat!`**

Si `create_chat!` lève une exception (contrainte DB, etc.), l'analyse est persistée en base sans `Chat` associé. Le job planifié plus tard appelle `analysis.chat.messages` sur un chat `nil` et plante avec `NoMethodError`.

```ruby
# Correction
def create
  Analysis.transaction do
    @analysis = Analysis.create!(user: current_user)
    @analysis.create_chat!
  end
  redirect_to add_pictures_analysis_path(@analysis)
end
```

---

**🔴 Critique — `app/controllers/messages_controller.rb:12-13` — Le job est déclenché même sans photos**

Le guard ligne 9 n'attache les photos que si elles sont présentes, mais `processing!` et `perform_later` sont toujours appelés. Une soumission sans photo crée un message vide, et le job envoie à l'IA un contexte sans image.

```ruby
# Correction
message.photos.attach(message_params[:photos]) if message_params[:photos].present?
message.save!

unless message.photos.attached?
  redirect_to add_pictures_analysis_path(@analysis), alert: "Veuillez fournir au moins une photo."
  return
end

@analysis.processing!
AnalyzeGarmentJob.perform_later(@analysis.id)
```

---

**🟠 Important — `app/services/openai_vision_service.rb:29` — `parsed["criteria"]` peut être `nil`**

Si l'IA omet la clé `"criteria"` ou retourne du JSON partiel, `parsed["criteria"].map` lève `NoMethodError`. Le job attrape ça en `failed!`, mais sans indication de la cause réelle.

```ruby
criteria_raw = parsed["criteria"] || []
criteria: criteria_raw.map { |c| { name: c["name"], detail: c["detail"], score: c["score"] } }
```

---

**🟠 Important — `app/jobs/analyze_garment_job.rb:15-16` — `rescue ActiveRecord::RecordNotFound` attrape trop large**

Si une `RecordNotFound` est levée *à l'intérieur* du service (p.ex. un `chat.messages` sur un chat absent), elle est interceptée par le premier `rescue`, l'analyse n'est pas marquée `failed!` et l'erreur est juste loggée silencieusement.

```ruby
rescue ActiveRecord::RecordNotFound => e
  # Distinguer : si c'est l'analyse elle-même qui est introuvable, on ne peut rien faire
  # Sinon, propager pour que le rescue StandardError marque l'analyse en failed
  raise unless e.model == "Analysis"
  Rails.logger.error "AnalyzeGarmentJob: Analysis ##{analysis_id} introuvable"
```

---

**🟠 Important — `app/views/analyses/add_pictures.html.erb:115-236` — La caméra n'est jamais stoppée à la navigation Turbo**

Avec Turbo Drive, naviguer hors de la page ne tue pas le flux `getUserMedia`. La caméra reste active (voyant LED allumé, ressources consommées).

```javascript
document.addEventListener("turbo:before-visit", function() {
  const video = document.getElementById("camera-feed")
  if (video?.srcObject) {
    video.srcObject.getTracks().forEach(t => t.stop())
    video.srcObject = null
  }
})
```

---

**🟡 Mineur — `app/controllers/messages_controller.rb:5` — Pas de guard sur le statut de l'analyse**

Si l'utilisateur soumet deux fois le formulaire (double-clic, rechargement), deux jobs sont déclenchés sur la même analyse, avec risque d'écrasement des critères.

```ruby
return redirect_to analysis_path(@analysis) if @analysis.processing? || @analysis.completed?
```

---

## 2. Sécurité

---

**🔴 Critique — `app/controllers/analyses_controller.rb:2` / `app/controllers/messages_controller.rb:2` — Absence totale d'autorisation**

N'importe qui peut accéder à `GET /analyses/:id`, `GET /analyses/:id/add_pictures` et `POST /analyses/:analysis_id/messages`. Les IDs étant des entiers séquentiels, un attaquant peut énumérer toutes les analyses existantes et même soumettre des photos sur l'analyse d'un autre utilisateur, déclenchant un appel IA à ses frais.

```ruby
# analyses_controller.rb - ajouter après find :
def authorize_analysis!
  return if @analysis.user.nil? || @analysis.user == current_user
  raise ActionController::RoutingError, "Not Found"
end
```

---

**🔴 Critique — Absence de rate limiting sur le déclenchement des jobs IA**

`POST /analyses/:analysis_id/messages` est public et chaque requête déclenche un appel API payant (GitHub Models / OpenAI). Aucune protection contre le spam : un script peut générer des centaines d'appels IA sans authentification.

Correction minimale : protéger `MessagesController#create` derrière `authenticate_user!` ou ajouter rack-attack en Gemfile.

---

**🟠 Important — `app/initializers/content_security_policy.rb` — CSP intégralement commentée**

La CSP Rails 8 est désactivée. Le résultat de l'analyse (texte venant de l'IA) est affiché tel quel via `<%= criterion.detail %>` — ERB échappe, donc pas de XSS direct, mais l'absence de CSP laisse le navigateur sans filet si une faille est introduite plus tard.

Activer et configurer `config/initializers/content_security_policy.rb`.

---

**🟠 Important — `app/views/shared/_navbar.html.erb:4,22` — Ressources externes hardcodées (Le Wagon template)**

Les lignes 4 et 22 chargent des images depuis `raw.githubusercontent.com` et `kitt.lewagon.com`. Ces domaines reçoivent l'IP de chaque visiteur. Les images sont des placeholders Le Wagon sans rapport avec le produit.

Supprimer ces URLs et utiliser des assets locaux.

---

**🟠 Important — Pas de validation MIME côté serveur pour les uploads photos**

L'attribut `accept="image/*"` est un contrôle purement navigateur. Le serveur accepte tout fichier via `permit(photos: [])`. Un attaquant peut uploader un PDF, un SVG avec JS, etc., qui seront ensuite encodés en base64 et envoyés à l'API OpenAI.

```ruby
ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

message_params[:photos].each do |upload|
  unless ALLOWED_TYPES.include?(upload.content_type)
    return redirect_to add_pictures_analysis_path(@analysis), alert: "Type de fichier non autorisé."
  end
end
```

---

**🟡 Mineur — `db/schema.rb:50` — IDs d'analyses séquentiels (IDOR facilité)**

Les analyses ont des IDs `bigserial` (1, 2, 3…). Sans token d'accès ni vérification d'appartenance, l'énumération est triviale. Envisager des UUIDs pour les analyses publiques.

---

## 3. Conventions et idiomes Rails 8

---

**🟠 Important — `app/views/analyses/show.html.erb:36-38` — Logique métier dans la vue**

Le calcul du score global (`total_score`, `max_score`, `global_pct`) est de la logique métier écrite en Ruby dans un bloc ERB. Rails-way : méthode sur le modèle ou helper.

```ruby
# app/models/analysis.rb
def global_score_percentage
  return 0 if criteria.empty?
  (criteria.sum(:score).to_f / (criteria.count * 10) * 100).round
end
```

---

**🟠 Important — `app/views/analyses/add_pictures.html.erb:105-236` — 130 lignes de JS inline**

Le JavaScript embarqué dans la vue devrait être un contrôle Stimulus (`app/javascript/controllers/camera_controller.js`). Stimulus est déjà présent dans le projet.

---

**🟡 Mineur — `app/jobs/analyze_garment_job.rb:26` — `vision_service` retourne une classe**

La méthode nommée `vision_service` retourne une *classe*, pas une instance. Rails-way : nommer `vision_service_class` ou `select_vision_service`.

---

**🟡 Mineur — `app/javascript/controllers/hello_controller.js` — Contrôleur de démo non supprimé**

Résidu du générateur Rails. À supprimer.

---

**🟡 Mineur — `app/views/shared/_navbar.html.erb:15-26` — Liens placeholder non nettoyés**

"Home → #", "Messages → #", "Action", "Another action" sont des placeholders Le Wagon. Trompeuses pour les utilisateurs et les futurs développeurs.

---

**🔵 Suggestion — `config/routes.rb` — `analyses` sans `index` ni `destroy`**

Les analyses orphelines (failed) s'accumulent en base sans route pour les lister ou les supprimer. Prévoir au moins une route de gestion pour les utilisateurs connectés.

---

## 4. Performance

---

**🟠 Important — `app/views/analyses/show.html.erb:36,37,56` — 3 requêtes SQL sur `criteria` pour la même association**

`criteria.sum(:score)`, `criteria.count`, puis `criteria.each` font chacun une requête SQL distincte. Une seule pré-charge en mémoire suffit.

```ruby
# analyses_controller.rb
def show
  @analysis = Analysis.includes(:criteria).find(params[:id])
end
```

Et dans la vue :
```erb
<% loaded = @analysis.criteria.to_a %>
<% total_score = loaded.sum(&:score) %>
<% max_score   = loaded.size * 10 %>
```

---

**🟠 Important — `app/services/openai_vision_service.rb:64` — `photo.download` charge l'image entière en RAM**

Avec 3 photos à 5-10 Mo chacune, on alloue 15-30 Mo par analyse dans la mémoire du job. Active Storage supporte le streaming, ou les URLs signées si Cloudinary/S3 est activé.

```ruby
# Alternative avec URL signée (si Cloudinary/S3) :
image_url: { url: photo.url(expires_in: 5.minutes) }
```

---

**🟡 Mineur — `app/services/stub_vision_service.rb:10` — `sleep 2` dans un thread de job**

Bloque un slot Solid Queue pendant 2 secondes en dev/test. Acceptable pour la démo mais à ne jamais activer en production.

---

**🟡 Mineur — `app/views/analyses/show.html.erb:16,28` — Polling infini sans timeout**

Si le job reste bloqué, le navigateur poll toutes les 2 secondes indéfiniment. Ajouter un timeout :

```javascript
let attempts = 0
const MAX_ATTEMPTS = 60  // 2 min
const pollingInterval = setInterval(function() {
  if (++attempts > MAX_ATTEMPTS) { clearInterval(pollingInterval); return; }
  fetch(...)
}, 2000)
```

---

## 5. Gestion d'erreurs et cas limites

---

**🟠 Important — `app/services/openai_vision_service.rb:24` — `JSON::ParserError` non distingué**

Si l'IA répond en dehors du JSON attendu (erreur de quota, réponse HTML d'un proxy, etc.), `JSON.parse` lève `JSON::ParserError`, capturée comme `StandardError` générique dans le job. L'analyse passe à `failed` sans log exploitable.

```ruby
begin
  parsed = JSON.parse(cleaned)
rescue JSON::ParserError => e
  raise "OpenAI returned non-JSON: #{raw.truncate(200)} — #{e.message}"
end
```

---

**🟠 Important — `app/services/openai_vision_service.rb:62-69` — Itération sur TOUS les messages, pas seulement les messages utilisateur avec photos**

`@analysis.chat.messages.each` inclut les messages `assistant` (sans photos). Si la logique évolue ou si le job est re-déclenché, on tente d'encoder en base64 des messages sans photos.

```ruby
@analysis.chat.messages.where(role: :user).each do |message|
  message.photos.each { ... }
end
```

---

**🟠 Important — `app/controllers/messages_controller.rb:5` — `@analysis.chat` peut être `nil`**

Si l'analyse a été créée sans transaction et que `create_chat!` a échoué, `chat.messages.build` lève `NoMethodError` et retourne une erreur 500.

```ruby
chat = @analysis.chat || raise(ActiveRecord::RecordNotFound, "Chat absent pour Analysis ##{@analysis.id}")
```

---

**🟡 Mineur — `add_pictures.html.erb:128-131` — Erreur caméra seulement visible dans le texte de scan**

Si `getUserMedia` est refusé, le message "Error: …" remplace le texte instructionnel mais les boutons restent actifs. `capturerPhoto` capture alors un canvas vide (image noire 0×0).

---

## 6. Lisibilité et maintenabilité

---

**🟠 Important — Mélange français/anglais dans les noms de fonctions JS**

`demarrerCamera`, `capturerPhoto`, `ouvrirUpload`, `tagPris`, `devantPris`, `derrierePris` sont en français dans un fichier majoritairement en anglais. Choisir une langue et s'y tenir.

---

**🟡 Mineur — `app/jobs/analyze_garment_job.rb:1` — Commentaires de chemin redondants**

`# app/jobs/analyze_garment_job.rb` en ligne 1 est superflu : le chemin est visible dans l'éditeur. Idem dans `openai_vision_service.rb:1-3` et `stub_vision_service.rb:1-3`.

---

**🟡 Mineur — `app/views/analyses/add_pictures.html.erb` — Styles inline massifs**

Des dizaines de `style="..."` inline (largeurs, border-radius, couleurs). Difficile à maintenir et à thématiser. Extraire dans des classes SCSS.

---

**🔵 Suggestion — `app/models/criterium.rb` — Nom de modèle non standard**

`Criterium` (latin singulier de `criteria`) est inhabituel. Si le projet n'est pas encore en production, renommer en `Criterion` évite la confusion permanente avec le `class_name:` explicite dans `Analysis`.

---

## 7. Tests

---

**🔴 Critique — Couverture de tests : 0%**

Tous les fichiers de test contiennent uniquement du boilerplate commenté. Aucun test réel n'existe.

Cas minimaux prioritaires à couvrir :

```ruby
# test/jobs/analyze_garment_job_test.rb
test "marks analysis completed with stub service" do
  ENV["VISION_SERVICE"] = nil
  analysis = Analysis.create!(status: :processing)
  analysis.create_chat!
  AnalyzeGarmentJob.perform_now(analysis.id)
  assert analysis.reload.completed?
  assert analysis.criteria.any?
end

test "marks analysis failed if service raises" do
  analysis = Analysis.create!(status: :processing)
  analysis.create_chat!
  StubVisionService.any_instance.stubs(:call).raises(StandardError, "erreur simulée")
  AnalyzeGarmentJob.perform_now(analysis.id)
  assert analysis.reload.failed?
end
```

---

**🟠 Important — Pas de test pour `OpenaiVisionService`**

Le parsing JSON, les cas limites (critères absents, JSON malformé, réponse vide) ne sont pas testés. C'est la logique la plus fragile du projet.

---

**🟠 Important — Pas de test d'intégration pour le flux complet**

Le chemin `create analysis → add pictures → submit → job → show results` n'est couvert par aucun test system/integration.

---

## Verdict global

Le projet est un MVP propre dans sa structure et lisible dans son intention, mais il présente **deux failles critiques bloquantes** avant toute mise en production : l'absence totale de contrôle d'accès (n'importe qui peut voir ou polluer n'importe quelle analyse) et la possibilité de déclencher des appels IA payants sans authentification ni rate limiting. La couverture de tests est nulle, ce qui rend toute évolution risquée. Le reste (N+1, logique dans les vues, caméra non stoppée) est facile à corriger mais secondaire.

**3 actions prioritaires :**

1. **🔴 Sécurité — Ajouter une vérification d'appartenance** sur `add_pictures`, `show` et `messages#create` : soit authentification obligatoire, soit un token secret par analyse (UUID en colonne, passé dans l'URL).

2. **🔴 Correctness — Encapsuler `save!` + `create_chat!` dans une transaction** et protéger `messages#create` contre les soumissions sans photos.

3. **🔴 Tests — Écrire au moins les tests du job** avec le `StubVisionService` (cas nominal + cas d'erreur), qui couvre le cœur fonctionnel du produit.
