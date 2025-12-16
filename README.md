# 🖥️ HAOS Kiosk Custom (Chromium Edition)

**HAOS Kiosk Custom** est un add-on pour Home Assistant OS permettant d'afficher vos tableaux de bord (Dashboards) directement sur un écran branché au port HDMI de votre serveur (Raspberry Pi, NUC, Mini-PC). Il utilise **Chromium** avec accélération matérielle.

---

## ⚙️ Options de l'Add-on

| Option | Description |
| :--- | :--- |
| **ha_url** | URL locale (défaut: http://localhost:8123). |
| **zoom_level** | Zoom de l'affichage (ex: 100, 120). |
| **rotate_display** | Rotation (normal, left, right, inverted). |
| **screen_timeout** | Mise en veille auto en secondes (0 = désactivé). |
| **onscreen_keyboard** | Active un clavier tactile visuel. |

---

## 📡 Contrôle via API (REST)

Vous pouvez piloter l'écran depuis vos automatisations HA (via Shell Command ou REST Command) :

* **Allumer l'écran** : `POST http://localhost:8080/display_on`
* **Éteindre l'écran** : `POST http://localhost:8080/display_off`
* **Rafraîchir** : `POST http://localhost:8080/refresh_browser`

---

## ⚠️ Notes Techniques

* **HDMI** : Branchez l'écran **avant** de démarrer l'add-on.
* **Privilèges** : L'add-on nécessite le mode **"Privilégié"** dans les paramètres pour accéder à la carte graphique.
* **Clavier/Souris** : Le curseur disparait automatiquement après quelques secondes d'inactivité.
