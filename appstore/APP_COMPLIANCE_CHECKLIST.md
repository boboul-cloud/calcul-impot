# Checklist conformite avant soumission

## Export Compliance (chiffrement)
Question Apple habituelle: l'app utilise-t-elle du chiffrement ?

Reponse pratique la plus frequente pour ce type d'app:
- Oui, l'app utilise le chiffrement standard fourni par iOS (HTTPS/TLS via URLSession).
- Pas de chiffrement proprietaire/maison.

Dans App Store Connect, suivez l'assistant Export Compliance et choisissez l'option correspondant a l'usage de chiffrement standard exempt (selon le formulaire en vigueur).

## Contenu et legal
- L'app n'est pas un service bancaire.
- L'app fournit une simulation informative, non contractuelle.
- Ajouter une mention legale dans la description et dans l'app (deja present dans l'app via textes explicatifs).

## Classe d'age
Recommandation de depart:
- Classe d'age standard (pas de contenu sensible, violence, etc.).

## Publicite / tracking
- Pas de publicite integree.
- Pas de tracking publicitaire.

## Avant envoi review
- Verifier que tous les placeholders [A_COMPLETER] sont remplaces.
- Verifier URL support + URL privacy policy accessibles publiquement.
- Verifier coherence entre App Privacy et comportement reel de l'app.
