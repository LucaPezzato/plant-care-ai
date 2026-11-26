<p align="center">
  <img src="assets/app_icon_1024.png" width="130" alt="Plant Care AI Icon" />
</p>

<h1 align="center">Plant Care AI</h1>

<p align="center">
  <strong>App Android personale in Flutter (Material 3 Expressive) per gestire le tue piante, programmare annaffiature e foto periodiche con calendario e notifiche locali, diagnosticare la salute tramite AI Multi-Provider, sincronizzare su Firebase e condividere il giardino con i familiari.</strong>
</p>

---

## ✨ Caratteristiche Principali

- **🎨 Material Design 3 Expressive + Material You (`dynamic_color`)**:
  - Superfici tonali dinamiche con tema Scuro / Chiaro / Sistema, palette botanica semantica e tipografia dual-font (`Plus Jakarta Sans` + `Inter`).
  - Logo botanico dedicato e splash screen nativo + animato in Flutter.
- **🌿 Gestione Piante & Riconoscimento AI**:
  - Aggiunta piante da **fotocamera, galleria o descrizione**: l'AI riconosce specie, esposizione luce, frequenza di annaffiatura, intervallo foto periodiche e note di cura.
  - Azione rapida **Annaffia** in 1 tap con barra stato idratazione e conto alla rovescia.
- **📅 Calendario Cure & Promemoria Locali**:
  - Calendario mensile interattivo con indicatori per annaffiature, foto check e attività completate + banner immediato per piante in ritardo.
  - Notifiche Android locali (`flutter_local_notifications` + `timezone`) programmabili all'orario preferito.
- **📸 Foto Periodiche & Diagnosi Salute AI**:
  - Foto salvate in locale nella memoria permanente dell'app e confrontate automaticamente con la foto e diagnosi precedente.
  - Report strutturato AI: punteggio salute (`1–10`), stato (`In salute`, `Attenzione`, `Critica`), trend (`In miglioramento`, `Stabile`, `In peggioramento`), criticità, azioni consigliate e proposta di aggiornamento frequenza acqua.
- **🤖 Multi-Provider AI con Elenco Modelli Live (`/models`)**:
  - **Google Gemini**, **OpenAI / ChatGPT** e qualsiasi server **OpenAI-compatibile** (**OpenRouter**, **Groq**, **Ollama**, **LM Studio**).
  - Scarica automaticamente i modelli aggiornati direttamente dagli endpoint `/models` di ciascun provider (con selettore ricercabile), senza dover aggiornare l'app.
  - Chiavi API salvate cifrate sul dispositivo tramite `flutter_secure_storage`.
- **☁️ Firebase Cloud Backup & Giardino Condiviso (Famiglia)**:
  - Backup automatico SQLite compresso con GZip su **Cloud Firestore** (accesso Google o Anonimo 1-Tap).
  - **Giardino Condiviso**: crea un giardino di famiglia con **codice invito a 6 caratteri** (es. `K7P-4M2`), sincronizza piante e annaffiature in tempo reale tra familiari e traccia chi ha annaffiato.

---

## 📚 Documentazione

- **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)**: Guida rapida per collegare `google-services.json` e configurare le regole Firestore per backup privato e giardini condivisi.

---

## 🚀 Avvio Rapido

```bash
# 1. Installa le dipendenze Flutter
flutter pub get

# 2. Analisi statica e test
flutter analyze
flutter test

# 3. Avvia sull'emulatore Android
./run_emulator.sh

# Oppure compila direttamente l'APK di debug
flutter build apk --debug
```
