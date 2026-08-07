# Planta Rolleras — Coop El Círculo

App para la planta: máquinas, roturas/repuestos/insumos faltantes, y estadísticas
de producción (kilos, errores, defectos) que vienen de las hojas de control
cargadas por foto (carpeta `sistema-control-produccion/`, sistema con Gemini + n8n).

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | Login (Supabase Auth) |
| `dashboard.html` | Panel: pestaña **Máquinas y eventos** (bitácora de roturas/repuestos/insumos) + pestaña **Producción** (gráficos de kilos, bien/mal, defectos, scrap) |
| `app.js` | Cliente Supabase, auth, CRUD |
| `sistema-control-produccion/1-supabase-schema.sql` | Esquema completo de producción (empresas/plantas/máquinas/operarios/bobinas), ya armado para Dottiplast pero genérico multi-empresa |
| `sistema-control-produccion/2-extension-eventos-y-auth.sql` | Extensión para esta app: tabla `usuarios` (login), tabla `eventos_maquina` (bitácora), permisos, y siembra de la empresa "Coop El Circulo" / planta "Rolleras" |
| `sistema-control-produccion/2-flujo-ingesta-y-consultas.json` | Workflow n8n: foto de la hoja de control → Gemini → Supabase (hay que apuntarlo a este proyecto nuevo, ver abajo) |

## Puesta en marcha

### 1. Supabase
1. Creá un proyecto nuevo en supabase.com (aparte del de tu negocio personal).
2. SQL Editor → correr **primero** `sistema-control-produccion/1-supabase-schema.sql` completo, y **después** `sistema-control-produccion/2-extension-eventos-y-auth.sql`.
3. **Authentication → Users → Add user**: creá tu primer usuario (email tipo `tunombre@coopelcirculo.com`, o el que prefieras, con contraseña). Copiá su UUID.
4. SQL Editor: `insert into usuarios (nombre, user_id) values ('Tu Nombre', 'EL-UUID-QUE-COPIASTE');`
5. Repetí 3-4 por cada persona que vaya a usar la app.

### 2. Esta app (index.html / dashboard.html / app.js)
1. En `app.js`, reemplazá `https://TU-PROYECTO.supabase.co` y `TU-ANON-KEY` por los datos de tu proyecto (**Project Settings → API**, la clave **anon/public**, nunca la service_role).
2. Deploy como estático en Easypanel con el `Dockerfile` incluido (igual que tus otras apps).

### 3. Flujo de ingesta (n8n) — para que la pestaña "Producción" tenga datos
El workflow que fotografía la hoja de control y la guarda en Supabase (carpeta
`sistema-control-produccion/`) hay que armarlo/apuntarlo a **este** proyecto nuevo:
1. Importá `2-flujo-ingesta-y-consultas.json` en tu n8n (uno nuevo, o un workflow
   aparte en el mismo n8n — no lo mezcles con el de Dottiplast).
2. Credenciales: Telegram (bot propio de coop el circulo), Google Gemini, y
   **Supabase de este proyecto nuevo** (service_role key).
3. En el nodo `ValidarDatos`, el campo `empresa` tiene que quedar en
   `"Coop El Circulo"` (así lo separa del resto). El campo `planta` en `"Rolleras"`
   o dejalo vacío (cae en "Planta principal" por defecto — está bien si tenés una sola).
4. Activá el workflow. Las máquinas se crean solas la primera vez que aparecen
   en una foto — no hace falta cargarlas a mano.

### 4. Uso diario
- **Máquinas y eventos**: cuando algo se rompe o falta un repuesto/insumo, tocás
  "+ Evento" en la máquina correspondiente, elegís el tipo y describís. Se marca
  "Resuelto" cuando se soluciona.
- **Producción**: gráficos de kilos, errores y defectos de las hojas de control
  cargadas por foto, con filtro de fechas.
