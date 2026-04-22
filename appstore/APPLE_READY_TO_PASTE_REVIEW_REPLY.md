# Apple Review - Texte pret a coller

## 1) App Review Information > Notes (EN)

Hello App Review Team,

Thank you for your feedback. Please find all requested information below.

1) Screen recording on physical device
- Device used: iPhone (physical device), iOS current public version.
- Video link: [PASTE VIDEO LINK HERE]
- The recording starts from app launch and shows the full core user flow:
  - Launch app and land on Home/Overview.
  - Enter household status and income values.
  - Open document import options and scan/import a tax document.
  - Show OCR extraction result and apply extracted values.
  - Navigate to Deductions and Credits page and enter sample values.
  - Open Assistant page, optionally enable AI with a user-provided OpenAI API key, and generate suggested tax boxes.
  - Run tax simulation and review tax details (brackets, quotient familial, decote).
  - Export PDF summary.
- Sensitive permission prompts shown in recording:
  - Camera permission prompt (used for document scanning).
- Not applicable in this app:
  - No account registration/login/deletion.
  - No in-app purchases/subscriptions.
  - No user-generated social content, reporting, or blocking.

2) App purpose and value
- The app helps individuals in France estimate personal income tax and understand how the amount is calculated.
- It solves the problem of complex tax estimation by providing:
  - guided input for household/income,
  - deductions/credits handling,
  - document OCR import support,
  - clear breakdown of the calculation,
  - PDF export of the estimate.
- Important: this is an informational simulator and not an official tax filing service.

3) Access instructions and test credentials
- No login is required.
- All main features are accessible immediately after launch.
- Suggested review path:
  - Home: set family situation and children.
  - Revenues: enter taxable income for declarant 1 (and declarant 2 for couple mode).
  - Deductions and advantages: add deductions, credits, and withholding amounts.
  - Assistant: optional AI guidance for tax boxes.
  - Export: generate and share PDF summary.
- Test credentials: not required.

4) External services/tools/platforms used for core functionality
- Tax config fetch (HTTPS):
  - https://raw.githubusercontent.com/boboul-cloud/tax-config/main/tax_config.json
  - https://cdn.jsdelivr.net/gh/boboul-cloud/tax-config@main/tax_config.json
- Optional AI features (only if user enters their own API key):
  - OpenAI API endpoint: https://api.openai.com/v1/chat/completions
- No third-party authentication service.
- No payment processor.
- No ad SDK.

5) Regional differences
- The app behavior is consistent across all regions.
- Functional scope is tax estimation for French tax use cases/content.

6) Regulated industry documentation
- The app does not provide regulated financial or tax advisory services.
- It is an informational estimate tool only and does not submit tax returns.
- Therefore, no special regulatory license documentation applies.

Additional technical clarification
- Data is primarily processed on device.
- AI is optional and disabled by default unless user provides their own OpenAI API key.
- The OpenAI API key is stored locally on the device (UserDefaults).

Review contact
- Name: Robert Oulhen
- Email: bob.oulhen@gmail.com
- Phone: 0668707219

Thank you.

## 2) Message court a envoyer dans Resolution Center (EN)

Hello,

Thank you for your message.
We have updated the App Review Information Notes with all requested items:
- physical-device screen recording link,
- app purpose and value,
- feature access instructions,
- external services used,
- regional behavior statement,
- regulated-industry clarification.

Please let us know if you need any additional detail.

Best regards,
Robert Oulhen

## 3) Version FR (reference interne)

Bonjour equipe App Review,

Merci pour votre retour. Nous avons ajoute dans Notes toutes les informations demandees:
1. lien de video enregistree sur appareil physique montrant le flux complet,
2. objectif de l'app et valeur utilisateur,
3. instructions d'acces aux fonctions principales (sans login),
4. services externes utilises,
5. confirmation du comportement regional,
6. clarification sur l'absence de service reglemente.

L'application est un simulateur informatif (pas un service officiel de declaration fiscale).

Cordialement,
Robert Oulhen
