# Configurazione Backup Cloud & Giardino Condiviso Firebase

**Plant Care AI** funziona al 100% offline con SQLite locale, e supporta tramite **Firebase Auth + Cloud Firestore**:
1. **Backup Cloud Personale** (SQLite compresso con GZip su `users/{uid}/backup/plant_care_db`).
2. **Giardino Condiviso (Famiglia)** in tempo reale (`gardens/{gardenId}` con codice invito a 6 caratteri).

## Passi per attivare Firebase

1. Vai su [Firebase Console](https://console.firebase.google.com/) e crea un progetto (o usa lo stesso progetto di `calorie-tracker-ai`).
2. Aggiungi una nuova app **Android** con package name:
   `com.example.plant_care_ai`
3. Scarica `google-services.json` e copialo in:
   `android/app/google-services.json`
4. In Firebase Console abilita:
   - **Authentication -> Sign-in method**: attiva **Google** e/o **Anonimo**.
   - **Firestore Database**: crea il database e imposta queste regole di sicurezza:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Backup personale privato
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Giardini condivisi tra familiari
    match /gardens/{gardenId} {
      // Consente la ricerca per inviteCode e l'accesso ai membri autenticati
      allow read: if request.auth != null;
      allow create: if request.auth != null
        && request.auth.uid in request.resource.data.memberUids;
      allow update: if request.auth != null
        && (request.auth.uid in resource.data.memberUids
            || request.auth.uid in request.resource.data.memberUids);

      match /{subcollection}/{docId} {
        allow read, write: if request.auth != null
          && request.auth.uid in get(/databases/$(database)/documents/gardens/$(gardenId)).data.memberUids;
      }
    }
  }
}
```

5. Ricompila l'app (`flutter run` o `flutter build apk --debug`): il plugin Gradle `com.google.gms.google-services` si attiva automaticamente non appena rileva `android/app/google-services.json`.
