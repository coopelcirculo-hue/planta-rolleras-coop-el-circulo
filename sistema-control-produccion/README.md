# Sistema de Control de Producción

El operario saca una foto de la hoja de control → todo lo demás es automático:
lectura con IA, validaciones, base de datos, estadísticas, dashboard en tiempo
real, reportes PDF/Excel y consultas en lenguaje natural.

## Archivos

| Archivo | Qué es |
|---|---|
| `1-supabase-schema.sql` (o los `bloque-*.sql`) | Esquema completo de la base (tablas, vistas, funciones) |
| `2-flujo-ingesta-y-consultas.json` | n8n: **un solo** Activador de Telegram + switch Foto/Texto — Foto va a Gemini→validación→Supabase; Texto va al agente de consultas |
| `4-flujo-reportes.json` | n8n: PDF diario/semanal/mensual + Excel, enviados automáticamente (disparador por horario) |
| `5-flujo-graficos-trimestral.json` | n8n: 2 gráficos de línea (kilos por máquina, errores por operario) del trimestre recién cerrado, enviados por Telegram el día 1 de ene/abr/jul/oct. Workflow independiente, no toca el de reportes. |
| `dashboard.html` | Dashboard web en tiempo real con filtros |

> ⚠️ Importá solo **2 workflows** en n8n (`2-flujo-ingesta-y-consultas.json` y `4-flujo-reportes.json`), no 3. Los archivos viejos `2-flujo-ingesta.json` y `3-flujo-consultas.json` quedan obsoletos: Telegram permite un solo webhook activo por bot, así que tener 2 workflows separados con su propio Activador de Telegram para el mismo bot hace que uno le robe el webhook al otro. Por eso ingesta y consultas ahora comparten un único trigger con un switch.

## Arquitectura

```
Foto (Telegram / formulario / cualquier app via webhook)
   → n8n → Gemini (lee la hoja, nunca inventa: marca ILEGIBLE)
   → Validaciones (obligatorios, fechas, pesos, duplicados)
        ├─ con errores  → aviso de qué revisar (no se guarda nada)
        └─ sin errores  → RPC cargar_parte en Supabase (transaccional)
                            ├─ producciones (1 por máquina+fecha+turno)
                            ├─ bobinas (1 registro por bobina)
                            ├─ operarios / maquinas (se crean solos)
                            ├─ defectos + bobina_defectos
                            ├─ scrap
                            └─ historial
Estadísticas = vistas SQL → siempre en tiempo real, no hay nada que recalcular
   ├─ dashboard.html (lee las vistas con el anon key + realtime)
   ├─ agente de consultas (SELECT de solo lectura vía consulta_lectura)
   └─ reportes programados (PDF con Gotenberg + Excel)
```

## Puesta en marcha

### 1. Supabase
1. Abrí el SQL Editor de tu proyecto y ejecutá `1-supabase-schema.sql` completo.
2. En **Database → Replication** activá realtime para la tabla `bobinas` (para que
   el dashboard se refresque solo al instante; si no, igual se refresca cada 2 min).

### 2. n8n
1. Importá los 3 JSON (menú ⋯ → *Import from File*).
2. Credenciales a asignar:
   - **Telegram API** (bot de @BotFather) → todos los nodos de Telegram.
   - **Google Gemini (PaLM) API** (key de aistudio.google.com) → nodo `LeerParte`
     y `Modelo de chat de Gemini`.
   - **Supabase API** (URL del proyecto + **service_role key**) → nodos Supabase
     y también en los nodos HTTP `GuardarParte` y `consultar_base` (usan la
     credencial de tipo Supabase).
3. Reemplazos a mano (buscar y pegar):
   - `https://TU-PROYECTO.supabase.co` → la URL de tu proyecto (en 2 nodos HTTP).
   - `PEGAR_CHAT_ID_AVISOS` → chat ID de Telegram donde avisar las cargas del formulario.
   - `PEGAR_CHAT_ID_REPORTES` → chat/grupo donde llegan los reportes.
   - `http://TU-GOTENBERG:3000` → URL del servicio Gotenberg (paso 3).
4. Activá los 3 workflows. La URL pública del **formulario web** aparece en el
   nodo "Formulario web" (sirve para cargar desde PC, y cualquier app puede
   hacer POST a ese mismo webhook).

### 3. Gotenberg (para los PDF)
En Easypanel creá un servicio nuevo con la imagen `gotenberg/gotenberg:8`,
puerto 3000, sin variables. Usá la URL interna del servicio en el nodo
`ConvertirPDF`. (Si todavía no lo montás, el Excel y todo lo demás funciona igual.)

### 4. Dashboard
1. En `dashboard.html` pegá `SUPABASE_URL` y `SUPABASE_ANON_KEY` (el **anon**, no el service_role).
2. Deploy como estático en Easypanel igual que tus otras webs (o abrilo directo
   en el navegador para probar). La seguridad ya está resuelta: el anon key solo
   puede leer las vistas, nunca escribir ni tocar las tablas.

## Multi-empresa / escalabilidad

- Todo cuelga de `empresas → plantas → maquinas`; las vistas incluyen `empresa_id`.
- Para otra empresa: en el flujo de ingesta cambiá el campo `empresa` del nodo
  `ValidarDatos` (o cloná el workflow con otro bot de Telegram por cliente).
- El dashboard se filtra agregando `.eq('empresa', 'Nombre')` a las dos consultas.
- Nuevas máquinas y operarios **no requieren carga previa**: se crean solos al
  aparecer por primera vez en una hoja.

## Validaciones implementadas

- Campos obligatorios: fecha y al menos una bobina (bloquean); operario, máquina,
  turno, estado y pesos faltantes generan advertencia.
- Fechas inválidas, futuras o de más de 60 días.
- Pesos fuera del rango habitual (10.000–100.000, ajustable en `ValidarDatos`).
- Bobinas repetidas: dentro de la misma hoja y contra lo ya cargado en la base.
- Ilegibles: Gemini tiene prohibido inventar; marca `ILEGIBLE` y el sistema lo
  convierte en advertencia con el detalle exacto de qué revisar.
- Parte duplicado (misma máquina+fecha+turno): agrega solo las bobinas nuevas y avisa.
