# Audit Prompt / RubyLLM & Préparation Ecobalyse — FIBR

> Date : 2026-06-04
> Auditeur : Claude Sonnet 4.6
> Périmètre : `analyze_garment_job.rb`, `config/initializers/ruby_llm.rb`, modèles, schéma DB

---

## Ce qui est déjà bien

- Migration `ruby-openai` → `ruby_llm` 1.15.0 **terminée** : aucun résidu de l'ancien gem dans le `Gemfile`.
- `openai_api_base` correctement pointé vers `https://models.inference.ai.azure.com` (endpoint GitHub Models actuel).
- Gestion des tempfiles exemplaire : tableau `@tempfiles` pour protéger du GC + bloc `ensure` pour le nettoyage.
- Prompt « NEVER INVENT » solide, gestion de l'étiquette illisible documentée, calibration 0-10 réaliste.
- Gestion des erreurs : `rescue StandardError` → `analysis.failed!`.

---

## A. Prompt / RubyLLM

### A1 — Parsing JSON brut au lieu de `with_schema`
**Priorité : haute**

**Constat** (`analyze_garment_job.rb:45-46`) : `response.content.gsub(/```json|```/, "").strip` + `JSON.parse(cleaned)`. Fragile : fences en majuscules, texte hors JSON, réponse tronquée.

**Recommandation** : utiliser la sortie structurée RubyLLM 1.x via `with_schema`. Définir un `RubyLLM::Schema` dans `app/schemas/garment_analysis_schema.rb` et passer `schema: GarmentAnalysisSchema` dans `chat.ask(...)`. La gem valide le JSON et retourne un Hash directement — plus besoin de `JSON.parse`.

---

### A2 — Le prompt vision n'extrait pas les attributs Ecobalyse
**Priorité : haute**

**Constat** (`analyze_garment_job.rb:86-141`) : le `system_prompt` cible uniquement la qualité textile. Les champs requis par Ecobalyse (`product_type`, composition normalisée, `Made in`, tricot/tissé) ne sont pas demandés, alors que GPT-4o traite déjà les mêmes photos.

**Recommandation** : étendre le `system_prompt` pour extraire ces champs dans une clé `ecobalyse_fields` du JSON de sortie, avec la règle `null` pour tout ce qui est illisible :
```
"ecobalyse_fields": {
  "product_type": "tshirt" | null,
  "composition": [{"fiber": "cotton", "pct": 80}, ...] | null,
  "country": "Bangladesh" | null,
  "construction": "knitted" | "woven" | "unknown"
}
```

---

### A3 — Champs de critères nullables en base → risque de données silencieusement invalides
**Priorité : haute**

**Constat** : `criteria.score` et `criteria.name` sont nullables (`db/schema.rb:64-65`). Sans validation, un score `nil` fausse le calcul de `global_pct` dans `show.html.erb:37`. `with_schema` (voir A1) résout ce point en forçant les types côté gem.

---

### A4 — `build_images` itère tous les messages, pas uniquement `role: :user`
**Priorité : moyenne**

**Constat** (`analyze_garment_job.rb:53-57`) : `analysis.chat.messages.flat_map` inclut les messages `assistant` (sans photos). Anodin aujourd'hui, mais problématique dès que le mini-chat Ecobalyse créera plusieurs messages avant un éventuel re-déclenchement du job.

**Recommandation** : `analysis.chat.messages.where(role: :user).flat_map { ... }`

---

### A5 — Le résumé IA est stocké mais jamais affiché
**Priorité : moyenne**

**Constat** : `save_results` (`analyze_garment_job.rb:77`) crée un message `assistant` avec `parsed["summary"]`, mais `show.html.erb` n'affiche que les critères et le score global. Le verdict textuel de l'IA est invisible pour l'utilisateur.

**Recommandation** : afficher `@analysis.chat.messages.where(role: :assistant).last&.content` dans `show.html.erb`, entre le card de score et le détail des critères.

---

### A6 — `assume_model_exists` absent de la configuration RubyLLM
**Priorité : basse**

**Constat** (`config/initializers/ruby_llm.rb`) : sans `assume_model_exists: true`, RubyLLM valide le nom du modèle contre sa liste interne. `"gpt-4o"` est connu aujourd'hui, mais tout alias GitHub Models ou version datée (`"gpt-4o-2024-11-20"`) lèverait une `UnknownModelError`.

**Recommandation** : `config.assume_model_exists = true` dans l'initializer.

---

### A7 — WIKI Technique désynchronisé après la migration
**Priorité : basse**

**Constat** : `WIKI_TECHNIQUE.md` (sections 4.3, 4.4, 6.1) décrit `StubVisionService` / `OpenaiVisionService` dans `app/services/`, la variable `OPENAI_API_KEY`, et l'endpoint `models.github.ai/inference`. Ces fichiers n'existent plus — `app/services/` est absent, la logique est inline dans le job, la variable est `GITHUB_TOKEN`, l'endpoint est `models.inference.ai.azure.com`.

---

## B. Ecobalyse (non encore implémenté)

### B1 — Aucune colonne pour les attributs extraits ni le résultat Ecobalyse
**Priorité : haute**

**Constat** (`db/schema.rb:45-52`) : la table `analyses` ne contient que `score` et `status`. Colonnes manquantes : `product_type`, `composition_json` (jsonb), `country_of_origin`, `fabric_construction`, `size`, `mass_kg`, `ecs_score` (µPts), `ecobalyse_web_url`.

---

### B2 — L'enum `status` ne distingue pas les deux phases
**Priorité : haute**

**Constat** (`analysis.rb:7`) : `{pending:0, processing:1, completed:2, failed:3}`. Impossible de distinguer « phase A terminée, mini-chat en attente » de « phase B Ecobalyse en cours ».

**Recommandation** : étendre l'enum en préservant les valeurs existantes :
```ruby
enum :status, {
  pending:              0,
  processing:           1,
  quality_complete:     2,   # phase A done, attributs Ecobalyse manquants
  ecobalyse_processing: 3,   # phase B en cours
  completed:            4,
  failed:               5
}
```

---

### B3 — Aucun service Ecobalyse
**Priorité : haute**

Pas de `app/services/ecobalyse_service.rb`. À créer avec :
- Endpoint : `POST https://ecobalyse.beta.gouv.fr/api/textile/simulator/detailed`
- Header : `Authorization: Bearer #{ENV.fetch('ECOBALYSE_TOKEN')}`
- Body requis : `{ product:, mass:, materials: [{id:, share:}] }`
- Gestion du `400 InvalidParametersError` et des timeouts
- Utiliser `/detailed` (pas `/simulator`) pour obtenir `webUrl` et le détail par étape

---

### B4 — Aucune table type×taille → masse
**Priorité : haute**

La stratégie dérive `mass_kg` d'une table `product_type × size`. Ni constante Ruby, ni table DB n'existent. À implémenter comme constante `GARMENT_MASS_KG` avant tout appel Ecobalyse.

---

### B5 — Aucun mapping fibres → IDs Ecobalyse
**Priorité : haute**

Le prompt retournera `"80% polyester, 20% cotton"`. L'API attend `[{id: "pes", share: 0.8}, {id: "coton", share: 0.2}]`. Créer une constante `FIBER_TO_ECOBALYSE_ID` couvrant les fibres courantes (coton, polyester, laine, nylon, viscose, élasthanne…).

---

### B6 — Aucun verrou de complétude avant l'appel Ecobalyse
**Priorité : haute**

La décision « assez d'infos pour appeler Ecobalyse ? » doit être en Ruby, pas confiée au LLM. Implémenter une méthode `ecobalyse_ready?` sur `Analysis` vérifiant `product_type.present?`, `mass_kg.present?`, `composition_json.present?`, et que la somme des pourcentages ≈ 100.

---

### B7 — Variable d'environnement Ecobalyse absente
**Priorité : moyenne**

`ECOBALYSE_TOKEN` n'est pas dans `.env`. À ajouter dans `.env`, dans les secrets Kamal (`.kamal/secrets`) et dans la config Heroku/infra de production.

---

### B8 — Affichage du score ECS non prévu
**Priorité : moyenne**

`show.html.erb` n'a aucune section pour `ecs_score`. La valeur brute en µPts est incompréhensible sans contexte. Prévoir une section « Impact environnemental » séparée visuellement de « Qualité », avec un repère par catégorie (ex. : moyenne t-shirt) et un lien vers `ecobalyse_web_url`.

---

## Top 5 des actions priorisées

| # | Action | Fichier(s) | Priorité |
|---|--------|-----------|----------|
| 1 | Étendre `system_prompt` pour extraire les attributs Ecobalyse (`ecobalyse_fields`) dans la même passe vision | `analyze_garment_job.rb` | **Haute** |
| 2 | Passer à `with_schema` au lieu de `JSON.parse` brut | `analyze_garment_job.rb` + `app/schemas/` | **Haute** |
| 3 | Migration : colonnes Ecobalyse sur `analyses` + extension de l'enum `status` | `db/migrate/` + `analysis.rb` | **Haute** |
| 4 | Créer `EcobalyseService` : appel `/detailed`, gestion `400`, token Bearer, mapping fibres → IDs | `app/services/ecobalyse_service.rb` | **Haute** |
| 5 | Ajouter `assume_model_exists: true` + mettre à jour le WIKI (supprimer références aux services supprimés) | `config/initializers/ruby_llm.rb` + `WIKI_TECHNIQUE.md` | **Basse** |
