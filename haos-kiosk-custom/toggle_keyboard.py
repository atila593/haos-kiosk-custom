import tkinter as tk
import subprocess
import sys

# --- FONCTION DE COMMANDE D-BUS ---
def toggle_keyboard(event):
    """Envoie la commande D-Bus pour basculer la visibilité du clavier Onboard."""
    subprocess.Popen([
        "dbus-send",
        "--type=method_call",
        "--print-reply",
        "--dest=org.onboard.Onboard",
        "/org/onboard/Onboard/Keyboard",
        "org.onboard.Onboard.Keyboard.ToggleVisible"
    ])

# --- CRÉATION ET CONFIGURATION DE LA FENÊTRE ---
root = tk.Tk()
root.overrideredirect(True) # Supprime la barre de titre et les décorations
root.attributes("-topmost", True) # Garde la fenêtre toujours au-dessus

# Calcule la position pour centrer le bouton au bas de l'écran
BUTTON_SIZE = 50 # Taille du bouton en pixels (50x50)
SCREEN_WIDTH = root.winfo_screenwidth()
SCREEN_HEIGHT = root.winfo_screenheight()

# Calcul des coordonnées :
# X : Centre de l'écran (Largeur / 2) moins la moitié de la taille du bouton
# Y : Presque en bas de l'écran (Hauteur - Taille du bouton)
POS_X = SCREEN_WIDTH // 2 - (BUTTON_SIZE // 2)
POS_Y = SCREEN_HEIGHT - BUTTON_SIZE

# Définit la géométrie de la fenêtre (taille et position)
root.geometry(f"{BUTTON_SIZE}x{BUTTON_SIZE}+{POS_X}+{POS_Y}")

# --- DÉTERMINATION DE LA COULEUR ---
# Si un argument est passé et est 'true', utilise le noir, sinon le blanc.
color = "black" if len(sys.argv) > 1 and sys.argv[1].lower() == "true" else "white"

# --- CRÉATION DU CANEVAS (le bouton cliquable) ---
# Le canevas a la même taille que la fenêtre (50x50)
canvas = tk.Canvas(root, width=BUTTON_SIZE, height=BUTTON_SIZE, highlightthickness=0, bg=color)
canvas.pack()

# Lie le clic gauche sur le canevas à la fonction de bascule du clavier
canvas.bind("<Button-1>", toggle_keyboard)

# Lance la boucle principale Tkinter
root.mainloop()
