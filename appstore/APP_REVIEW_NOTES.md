# App Review Notes (Apple)

## Sign-in
- Aucun compte utilisateur requis.
- L'app est pleinement utilisable sans connexion.

## Fonctions reseau
- Recuperation de la configuration fiscale depuis :
  - https://raw.githubusercontent.com/boboul-cloud/tax-config/main/tax_config.json
  - https://cdn.jsdelivr.net/gh/boboul-cloud/tax-config@main/tax_config.json
- Fonction optionnelle d'assistance IA via OpenAI si l'utilisateur renseigne sa propre cle API.

## IA (optionnel)
- L'utilisateur peut saisir sa cle API OpenAI dans l'app (stockee localement sur l'appareil via UserDefaults).
- Sans cle API, l'app reste fonctionnelle avec des heuristiques locales.
- Les contenus envoyes a OpenAI sont des textes fournis par l'utilisateur (demande chat ou texte OCR), uniquement pour produire des suggestions fiscales.

## Permissions
- Camera : utilisee pour scanner des documents fiscaux.
- Bibliotheque Photos : selection de photos/PDF fiscaux via le picker systeme.

## Export et partage
- L'app genere un PDF de simulation et utilise le partage systeme iOS.

## Clause importante
- L'app est un outil de simulation et d'aide a la saisie.
- Elle ne remplace pas une declaration fiscale officielle ni un conseil professionnel.

## Contact review
- Nom : Robert Oulhen
- Email : bob.oulhen@gmail.com
- Telephone : 0668707219
