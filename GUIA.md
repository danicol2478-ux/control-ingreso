# Guía: de este proyecto a la app instalada en tu celular Android

## ¿Qué hay en esta carpeta?

```
control_ingreso/
├── lib/
│   └── main.dart            ← TODO el código de la app (lo que ves en pantalla y la lógica)
├── pubspec.yaml             ← la "lista de compras": nombre de la app y librerías que usa
├── .github/workflows/
│   └── construir-apk.yml    ← receta para que GitHub fabrique el .apk por ti
└── GUIA.md                  ← esta guía
```

Un **.apk** es el archivo instalador de una app de Android, como un `.exe` en Windows.
Para fabricarlo hace falta "compilar" el código. Tienes dos caminos:

```
 CAMINO A (recomendado)                         CAMINO B
 GitHub lo compila por ti                       Tu PC lo compila
 ─────────────────────────                      ─────────────────────────
 No instalas nada pesado                        Instalas Flutter + Android Studio (~10 GB)
 Necesitas cuenta gratis en GitHub              Sirve para modificar y probar más rápido
 Tarda ~8 minutos                               La primera vez tarda bastante más
```

---

## CAMINO A: GitHub fabrica el APK (sin instalar nada)

```
 📁 Proyecto ──subir──► 🌐 GitHub ──compila (8 min)──► 📦 app-release.apk ──► 📱 WhatsApp ──► instalar
```

### Paso 1: crear la cuenta
Entra a **github.com**, toca **Sign up** y crea una cuenta gratis con tu correo.

### Paso 2: crear un repositorio (una "carpeta en internet")
1. Arriba a la derecha toca **+** → **New repository**.
2. En *Repository name* escribe: `control-ingreso`.
3. Deja marcado **Public** y toca **Create repository**.

### Paso 3: subir los archivos
1. En la página del repositorio toca el enlace **uploading an existing file**.
2. Arrastra **el contenido** de la carpeta `control_ingreso` (las carpetas `lib`, `.github` y el archivo `pubspec.yaml`).

> ⚠️ **Ojo con la carpeta `.github`:** en Windows empieza con punto y a veces queda oculta.
> En el Explorador de archivos ve a **Vista → Mostrar → Elementos ocultos**.
> Si al arrastrar no se sube, créala a mano: en GitHub toca **Add file → Create new file**,
> escribe como nombre `.github/workflows/construir-apk.yml` (las `/` crean las carpetas)
> y pega adentro el contenido del archivo.

3. Abajo toca **Commit changes** (significa "guardar los cambios").

### Paso 4: esperar a que se fabrique el APK
1. Arriba toca la pestaña **Actions**.
2. Verás "Construir APK" con un círculo amarillo 🟡 girando: está trabajando.
3. Cuando cambie a ✅ verde, ya está listo (unos 8 minutos).
   - Si sale ❌ rojo, toca el nombre, abre el paso que falló y copia el mensaje de error para revisarlo.

### Paso 5: descargar el APK
1. Toca la ejecución que quedó en ✅.
2. Abajo, en **Artifacts**, toca **control-ingreso-apk**.
3. Se descarga un `.zip`. Ábrelo: adentro está **app-release.apk**.

### Paso 6: mandarlo por WhatsApp e instalar
1. Envíate el archivo **app-release.apk** por WhatsApp (como documento).
2. En el celular, abre el archivo desde WhatsApp.
3. Android dirá *"Por tu seguridad, tu teléfono no puede instalar apps desconocidas de esta fuente"*.
   Toca **Configuración** → activa **Permitir de esta fuente** → regresa.
4. Toca **Instalar**. Si aparece Play Protect advirtiendo, toca **Instalar de todas formas**
   (es normal: la app no viene de la Play Store).
5. Aparece el ícono **Control Ingreso** en tu celular. 🎉

---

## CAMINO B: compilar en tu PC con VS Code

1. Instala **Flutter** siguiendo **docs.flutter.dev/get-started/install** (elige Windows → Android).
   Eso incluye instalar **Android Studio**.
2. En VS Code instala la extensión **Flutter**.
3. Abre una terminal en la carpeta donde quieres el proyecto y escribe:
   ```
   flutter create --org co.evento control_ingreso
   ```
4. Reemplaza `lib/main.dart` y `pubspec.yaml` por los de esta carpeta.
5. Abre `android/app/src/main/AndroidManifest.xml` y, arriba de la línea `<application`, pega:
   ```xml
   <uses-permission android:name="android.permission.CAMERA"/>
   ```
6. En la terminal:
   ```
   flutter pub get
   flutter build apk --release
   ```
7. El archivo queda en `build/app/outputs/flutter-apk/app-release.apk`. Sigue el **Paso 6** de arriba.

**Para probar mientras programas:** conecta el celular por cable USB, activa la
*Depuración USB* (en Opciones de desarrollador) y escribe `flutter run`.

---

## Cómo se usa la app

```
 ┌──────────────────────────────┐
 │ Control de ingreso   👥  ⋮   │ ← 👥 ver invitados · ⋮ descargar Excel / cambiar lista
 │ [1. Confirmar][ 2. Ingreso ] │ ← en qué paso estás
 │ ┌──────────────────────────┐ │
 │ │   cámara                 │ │
 │ │  ┌────────────────────┐  │ │ ← ponga aquí el código de la cédula, ACOSTADO
 │ │  └────────────────────┘  │ │
 │ │                      🔦  │ │ ← linterna
 │ └──────────────────────────┘ │
 │ ┌──────────────────────────┐ │
 │ │ Puede ingresar           │ │ ← 🟢 verde / 🟡 amarillo / 🔴 rojo
 │ │ María Fernanda Gómez     │ │
 │ └──────────────────────────┘ │
 │ [Escribir cédula a mano][Buscar]
 │  20     12      5      3     │ ← total · pendientes · confirmados · ingresaron
 └──────────────────────────────┘
```

1. **Primera vez:** toca **Cargar Excel** y elige `invitados_evento.xlsx` (debe estar en el celular,
   por ejemplo en Descargas) o toca **Usar lista de ejemplo**.
2. El celular pide permiso de cámara: toca **Permitir**.
3. **Paso 1, Confirmar:** escanea la cédula → queda *Confirmado*.
4. **Paso 2, Ingreso:** cambia a "2. Ingreso" y escanea de nuevo → *Puede ingresar*.
5. **Al final:** menú ⋮ → **Descargar Excel actualizado**. Lo puedes mandar por WhatsApp.

**No necesita internet.** Todo se guarda en el celular, aunque cierres la app.

## Cómo encuentra el número en la cédula

El código de barras de atrás de la cédula amarilla (PDF417) guarda varios datos seguidos.
El número va con ceros adelante y luego vienen los apellidos:

```
 ...0043840109GOMEZ  RESTREPO  MARIA  FERNANDA ... O+
    └────┬───┘
   número de cédula
```

La app busca cada cédula de la lista dentro de ese texto (función `buscarCedula` en `main.dart`).
