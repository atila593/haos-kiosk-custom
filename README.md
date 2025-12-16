# 🖥️ HAOS Kiosk Custom (Chromium Edition)

[cite_start]**HAOS Kiosk Custom** est un add-on pour Home Assistant OS qui permet d'afficher vos tableaux de bord (Dashboards) directement sur un écran branché au port HDMI de votre serveur (Raspberry Pi, NUC, Mini-PC). [cite_start]Il utilise **Chromium** avec accélération matérielle pour une fluidité maximale.

## 🚀 Fonctionnalités principales

* [cite_start]**Affichage Local** : Lance un serveur Xorg et Chromium sur la machine HAOS.
* [cite_start]**Connexion Automatique** : Optimisé pour les **Trusted Networks** afin d'éviter la saisie de mots de passe.
* [cite_start]**API de Contrôle (REST)** : Serveur Python intégré pour piloter l'écran (On/Off, Refresh, état) via des requêtes HTTP sur le port 8080 par défaut.
* [cite_start]**Haute Personnalisation** : Gestion du zoom (10 à 1000%), de la rotation d'écran (normal, left, right, inverted), et du mode sombre.
* [cite_start]**Support Tactile** : Mappage automatique des écrans tactiles et détection des périphériques d'entrée.

---

## 🛠️ Installation

1. Dans votre instance Home Assistant, allez dans **Paramètres** > **Greffons** (Add-ons).
2. Cliquez sur **Boutique d'add-ons** en bas à droite.
3. Cliquez sur les **trois points** (en haut à droite) et choisissez **Dépôts** (Repositories).
4. Ajoutez l'URL suivante : `https://github.com/atila593/haos-kiosk-custom`
5. Cherchez **HAOS Kiosk Custom** dans la liste et cliquez sur **Installer**.

---

## 🔐 Configuration de l'Auto-Login (Indispensable)

Pour que le kiosque se connecte sans intervention humaine, vous devez configurer les **Trusted Networks** (Réseaux de confiance) dans votre fichier `configuration.yaml` :

```yaml
homeassistant:
  auth_providers:
    - type: trusted_networks
      trusted_networks:
        - 127.0.0.1
        - ::1
      allow_bypass_login: true
    - type: homeassistant
