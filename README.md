# LAMP + GLPI 10 - Installation Automatique

Script d'installation complète **LAMP sécurisée + GLPI 10.x** pour **Debian/Ubuntu**.  
Testé et optimisé pour les environnements de production.

**Version 3.6** - Timezone Europe/Paris intégrée + Fix sécurité

---

## ✨ Installation en 1 commande

```bash
wget -q https://raw.githubusercontent.com/Crypt0Dock/lamp-glpi-installer/main/setup-lamp_glpi.sh -O - | sudo bash
ou
curl -s https://raw.githubusercontent.com/Crypt0Dock/lamp-glpi-installer/main/setup-lamp_glpi.sh | sudo bash
```

## 📋 Ce que ça installe

### Stack LAMP Complet
- **Apache 2** : Serveur web haute performance
- **PHP 8.3-FPM** (Sury) : Dernière version stable  
- **MariaDB** : Base de données compatible MySQL
- **GLPI 10.0.14** : Système d'assistance et gestion d'assets

---

## 🚀 Accès GLPI

Après installation (~5-10min) :

```
🌐 Accès GLPI :
  → http://IP-du-serveur/
  → http://glpi.local/ (si DNS configuré)

🔐 Identifiants par défaut GLPI :
  Utilisateur : glpi
  Mot de passe : glpi
```

**⚠️ IMPORTANT** : Change **tous** les mots de passe après première connexion !

---

## 🗄️ Base de données

Identifiants sauvegardés dans : `/root/glpi-credentials.txt`

```
DB : glpidb
User : glpi_user
Pass : [généré aléatoirement & sécurisé]
```

**Vérifier la connexion :**
```bash
mysql -u glpi_user -p glpidb -e "SELECT @@global.time_zone;"
# Doit retourner : Europe/Paris
```

---

## 🛠️ Prérequis

- **Debian 11/12** ou **Ubuntu 20.04/22.04/24.04**
- **Accès root** (`sudo`)
- **Connexion Internet** sortante
- **~2GB RAM minimum** pour GLPI
- **WGET/CURL** pour pull le script

---

## 🔧 Personnalisation

Tu peux modifier ces variables en haut du script :

```bash
GLPI_VERSION="10.0.14"   # Version GLPI
GLPI_DB="glpidb"         # Nom de la BDD
TIMEZONE="Europe/Paris"  # Timezone système
```

---

## 🤖 À propos & Transparence

> **Ce projet a été réalisé par Simon (étudiant TSSR) avec l'assistance d'une IA.**  
> 
> **L'IA a aidé pour :**
> - Création & refactoring du script bash (v1)
> - Simplification logique `configure_php()` 
> - Rédaction README & dépannage
> - Optimisation des bonnes pratiques sécurité
>
> **J'ai personnellement :**
> - Testé le script en environnement réel (Debian/Ubuntu)
> - Identifié & rapporté les bugs (timezone, syntaxe bash)
> - Adapté les configurations à mes besoins pro
> - Validé chaque étape et les choix techniques
> - Utilisé en production pour GLPI 10.x

---

## 🐛 Support & Contribution

- **Issues** : Ouvre une issue avec logs (`/var/log/lamp-glpi-setup-*.log`)
- **Améliorations** : Pull requests bienvenues !
- **Questions** : Discussion GitHub

---

## 📄 Licence

**MIT License** - Utilise librement, modifie, redistribue.


