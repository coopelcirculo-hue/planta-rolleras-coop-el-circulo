# Planta Rolleras — Coop El Círculo

App para la planta: máquinas, roturas/repuestos/insumos faltantes, y estadísticas
de producción (kilos, errores, defectos) que vienen de las hojas de control
cargadas por foto (carpeta `sistema-control-produccion/`, sistema con Gemini + n8n).

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | Login (Supabase Auth) |
| `dashboard.html` | Panel: pestaña **Monitoreo** (qué está haciendo cada máquina ahora) + **Máquinas y eventos** (bitácora de roturas/repuestos/insumos) + **Producción** (gráficos de kilos, bien/mal, defectos, scrap) |
| `app.js` | Cliente Supabase, auth, CRUD |
| `sistema-control-produccion/SUPABASE-COMPLETO.sql` | **El único SQL que hay que correr.** Producción (empresas/plantas/máquinas/operarios/bobinas + vistas + RPC para n8n) y app de planta (`usuarios`, `eventos_maquina`, permisos), ya adaptado a Coop El Círculo / planta Rolleras |
| `sistema-control-produccion/1-supabase-schema.sql` y `bloque-*.sql` | Versión original del esquema (Dottiplast). Quedan de referencia — **no correrlos**, los reemplaza `SUPABASE-COMPLETO.sql` |
| `sistema-control-produccion/2-flujo-ingesta-y-consultas.json` | Workflow n8n: foto de la hoja de control → Gemini → Supabase (hay que apuntarlo a este proyecto, ver abajo) |

## Puesta en marcha

### 1. Supabase
Proyecto: `yequwsdaqbihkmjtyuvm` (org `coopelcirculo-hue's`, plan free).

1. SQL Editor → pegar y ejecutar **`sistema-control-produccion/SUPABASE-COMPLETO.sql`** entero, una sola vez.
   *(Si ya lo corriste antes de que existiera el monitoreo, corré además
   `sistema-control-produccion/3-monitoreo-maquinas.sql`.)*
2. **Authentication → Users → Add user**: creá tu primer usuario (email tipo `tunombre@coopelcirculo.com`, con contraseña). Copiá su UUID.
3. SQL Editor: `insert into usuarios (nombre, user_id) values ('Tu Nombre', 'EL-UUID-QUE-COPIASTE');`
4. Repetí 2-3 por cada persona que vaya a usar la app.

> El usuario se crea con un email cualquiera (puede ser ficticio, tipo `@coopelcirculo.com`);
> en la pantalla de login se escribe solo la parte de antes del `@`.

### 2. Esta app (index.html / dashboard.html / app.js)
`app.js` ya está apuntado a ese proyecto (URL + anon key). El anon key es público
por diseño: la seguridad la dan las políticas RLS, no el secreto de la clave.

Deploy gratis con GitHub Pages (repo público) o Cloudflare Pages, o en Easypanel
con el `Dockerfile` incluido.

### 3. Flujo de ingesta (n8n) — para que la pestaña "Producción" tenga datos

Importá **`sistema-control-produccion/1-flujo-ingesta-COOP-EL-CIRCULO.json`**
(⋯ → *Import from File*). Ya viene con la URL de este Supabase, `empresa: "Coop El Circulo"`
y `planta: "Rolleras"` — no hay que tocar código.

Falta completar 4 cosas, todas dentro de n8n:

| Qué | Dónde se saca | Nodos que la usan |
|---|---|---|
| **Credencial Telegram** | Bot nuevo con [@BotFather](https://t.me/BotFather) (`/newbot`) | Activador de Telegram, ObtenerImagen, EnviarConfirmacion, AvisarErrores, RespuestaTexto |
| **Credencial Google Gemini** | API key en [aistudio.google.com](https://aistudio.google.com/apikey) | LeerParte, Modelo de chat de Gemini |
| **Credencial Supabase** | Project Settings → API → **service_role** key (no la anon) | GuardarParte, consultar_base |
| **Chat ID de avisos** | Reemplazar `PEGAR_CHAT_ID_AVISOS` (2 lugares) por el chat/grupo destino | EnviarConfirmacion, AvisarErrores |

> Para sacar el chat ID: mandale un mensaje al bot desde el grupo y abrí
> `https://api.telegram.org/bot<TU_TOKEN>/getUpdates` — el número está en `chat.id`.

Después activá el workflow. Sacan una foto de la hoja de control por Telegram y
Gemini la lee, valida y guarda. Las máquinas que aparezcan en las fotos se crean
solas (si ya las cargaste a mano con el mismo número, se reutilizan).

> ⚠️ Si tenés otro bot de Telegram corriendo en el mismo n8n (el de Dottiplast),
> usá un bot **distinto** para este: Telegram permite un solo webhook activo por
> bot, y si no uno le roba el webhook al otro.

### 4. Uso diario
- **Monitoreo**: el tablero de qué está haciendo cada máquina *ahora*. Con
  "Cambiar estado" registrás si está **produciendo** (medida + presentación, ej.
  `45x60x20` / `x24 Dottiplast`), **parada** (con motivo: cambio de cinta,
  repuesto, sin material...) o **apagada**. Cada cambio cierra el tramo anterior,
  así queda el historial completo con duraciones (botón 🕘). Se refresca solo
  cada minuto.
- **Máquinas y eventos**: cuando algo se rompe o falta un repuesto/insumo, tocás
  "+ Evento" en la máquina correspondiente, elegís el tipo y describís. Se marca
  "Resuelto" cuando se soluciona.
- **Producción**: gráficos de kilos, errores y defectos de las hojas de control
  cargadas por foto, con filtro de fechas.

> **Las máquinas** se pueden cargar a mano desde Monitoreo → "+ Agregar máquina"
> (poné el mismo número que figura en la hoja de control), y además se crean solas
> la primera vez que n8n procesa una foto con esa máquina.
