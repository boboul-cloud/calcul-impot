# App Privacy - Reponses proposees (App Store Connect)

Important : ces reponses sont basees sur le code actuel. Verifier avant soumission finale.

## 1) Does this app collect data?
Reponse recommandee : YES

Justification :
- Si l'utilisateur active l'assistance IA et renseigne sa cle OpenAI, du contenu saisi par l'utilisateur peut etre transmis a OpenAI pour traitement (chat fiscal / parsing OCR).
- Meme sans backend proprietaire, Apple peut considerer cela comme collecte via service tiers.

## 2) Data used to track users?
Reponse recommandee : NO

## 3) Data linked to the user's identity?
Reponse recommandee : NO (dans l'etat actuel)

Condition :
- Vous ne reliez pas ces donnees a un compte interne, un identifiant publicitaire, ou un profil utilisateur.

## 4) Data types potentiellement concernes
Selection prudente recommandee :
- User Content > Other User Content
  - Purpose: App Functionality
  - Linked to user: No
  - Used for tracking: No

Selon votre interpretation juridique/conformite, vous pouvez aussi evaluer :
- Sensitive Info (si vous considerez les donnees fiscales comme sensibles)
- Financial Info (si vous qualifiez certains champs fiscaux ainsi)

Si vous les cochez, garder les memes attributs :
- Purpose: App Functionality
- Linked to user: No
- Tracking: No

## 5) Privacy policy URL
Obligatoire. Utiliser une URL publique vers privacy-policy.html.

## 6) Points a garder coherents
- La fiche App Privacy doit correspondre exactement au comportement reel de l'app.
- Si vous ajoutez analytics, crash tracking tiers, pub, login, etc., il faudra mettre a jour cette section.
