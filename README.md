# Devis PPSOLAR — application tablette

Application Android (Flutter) de gestion de devis pour [ppsolar.fr](https://ppsolar.fr),
boutique de matériel photovoltaïque et de climatisation (marques PPSOLAR et PPCLIM).
Elle se connecte à WordPress/WooCommerce via l'API REST d'un plugin maison (solar-quotes).

## Fonctionnalités

- **Devis multi-marques** : création, édition, duplication, renumérotation, PDF, statuts
  (brouillon, envoyé, accepté, refusé, converti, expiré)
- **Ajout rapide** : les accessoires récurrents (goulottes et leurs angles, cuivre,
  condensat, pompe de relevage…) en cartes groupées, un appui = une ligne de devis
- **Recherche produits et clients** directement dans le catalogue WooCommerce
- **Fiche de visite technique** : surfaces, liaisons frigorifiques et électriques,
  dénivelés, pompe de relevage, support d'unité extérieure — relevée sur place
- **Dossier de chantier** : photos annotées au doigt (traits + pictogrammes métier),
  notes, deux phases (visite / fin de chantier), **hors-ligne avec synchro automatique**
- **Signature en ligne** côté client, conversion en commande WooCommerce,
  email « commande complète » pour la prise de rendez-vous

## Stack

- Flutter / Dart (Material 3, typographie Poppins embarquée)
- API REST WordPress (authentification par mot de passe d'application)
- SQLite (sqflite) pour le travail hors-ligne du dossier de chantier

## Lancer le projet

```bash
flutter pub get
flutter run
```

Au premier lancement, renseigner l'adresse du site WordPress, l'identifiant
et un mot de passe d'application.

## Licence

Projet développé pour PPSOLAR — code publié à titre de démonstration.