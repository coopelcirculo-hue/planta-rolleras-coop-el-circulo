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
| `sistema-control-produccion/SUPABASE-COMPLETO.sql` | **El único SQL que hay que correr.** Producción (empresas/plantas/máquinas/operarios/bobinas + vistas + RPC para n8n) y app de planta (`usuarios`, `eventos_maquina`, permisos), ya adaptado a Coop El Círculo / planta Rolleras |
| `sistema-control-produccion/1-supabase-schema.sql` y `bloque-*.sql` | Versión original del esquema (Dottiplast). Quedan de referencia — **no correrlos**, los reemplaza `SUPABASE-COMPLETO.sql` |
| `sistema-control-produccion/2-flujo-ingesta-y-consultas.json` | Workflow n8n: foto de la hoja de control → Gemini → Supabase (hay que apuntarlo a este proyecto, ver abajo) |

## Puesta en marcha

### 1. Supabase
Proyecto: `yequwsdaqbihkmjtyuvm` (org `coopelcirculo-hue's`, plan free).

1. SQL Editor → pegar y ejecutar **`sistema-control-produccion/SUPABASE-COMPLETO.sql`** entero, una sola vez.
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
