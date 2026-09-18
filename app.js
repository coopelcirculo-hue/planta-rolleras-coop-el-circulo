// ── Supabase ──────────────────────────────────────────────────────────────────
const SB = window.supabase.createClient(
  "https://yequwsdaqbihkmjtyuvm.supabase.co",
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InllcXV3c2RhcWJpaGttanR5dXZtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Nzk1MTcsImV4cCI6MjEwMTQ1NTUxN30.6M_UMFBvd3thFlDEwiZZwjXkAAGxXnE-IUFYsS1Xcj0"
);
const SUPABASE_CONFIGURADO = true;

// Nombre de empresa usado en el esquema multi-empresa (debe coincidir con lo que
// manda el flujo de ingesta de n8n en el campo "empresa" de cada hoja de control).
const EMPRESA = "Coop El Circulo";

// Formulario de n8n que lee la foto de la hoja con IA y la guarda en Supabase.
// La app le manda la foto directamente acá, sin que haya que salir del dashboard.
// Si en n8n se reimporta el workflow, este id cambia y hay que actualizarlo.
const N8N_FORM_URL = "https://asd-n8n.8mjdss.easypanel.host/form/f4d44909-5d6d-466c-b13e-9017ae9ac21e";

// ── Colores ───────────────────────────────────────────────────────────────────
const O="#f59e0b",D="#111827",CA="#1a2232",CB="#1F2937",BR="#2d3748",GR="#9CA3AF",W="#F8FAFC",RE="#ef4444",GN="#22c55e",BL="#60a5fa",PU="#a78bfa";

// ── Helpers ───────────────────────────────────────────────────────────────────
// Una fecha sola ("2026-08-07") la interpreta el navegador como medianoche UTC,
// y en Argentina (UTC-3) eso cae el día anterior. Por eso se formatea a mano.
const fdate = d => {
  if (typeof d === "string") {
    const m = d.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (m) return m[3] + "/" + m[2] + "/" + m[1];
  }
  return new Date(d).toLocaleDateString("es-AR");
};
const fnum = n => (Number(n)||0).toLocaleString("es-AR");
const hoyIso = () => { const d=new Date(); return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0"); };
const haceDiasIso = n => { const d=new Date(Date.now()-n*86400000); return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0"); };

// ── Estilos inline reutilizables ──────────────────────────────────────────────
const inp = {width:"100%",background:D,border:"1px solid "+BR,borderRadius:8,padding:"10px 12px",color:W,fontSize:13,boxSizing:"border-box",outline:"none",fontFamily:"Montserrat,sans-serif"};
const Btn = (bg,col,extra={}) => ({background:bg,color:col,border:"1px solid "+(bg==="transparent"?BR:bg),borderRadius:8,padding:"10px 18px",cursor:"pointer",fontSize:13,fontWeight:700,fontFamily:"Montserrat,sans-serif",...extra});

// ── Auth (Supabase Auth) ────────────────────────────────────────────────────
const AUTH_DOMAIN = "@coopelcirculo.com";
let _perfil = null;

const emailFromUsuario = u => u.includes("@") ? u : u.trim().toLowerCase()+AUTH_DOMAIN;

const initAuth = async () => {
  const {data:{session}} = await SB.auth.getSession();
  if(!session){ _perfil=null; return null; }
  const {data} = await SB.from("usuarios").select("*").eq("user_id",session.user.id).single();
  if(!data || data.activo===false){ await SB.auth.signOut(); _perfil=null; return null; }
  _perfil = {nombre:data.nombre, usuarioId:data.id};
  return _perfil;
};

// Devuelve {ok:true} o {ok:false, detalle:"..."} para poder mostrar el motivo real
// del fallo (no siempre es la contraseña: puede faltar la fila en `usuarios`).
const doLogin = async (usuario,password) => {
  const email = emailFromUsuario(usuario);
  const {error} = await SB.auth.signInWithPassword({email,password});
  if(error) return {ok:false, detalle:"Auth: "+error.message+" (email probado: "+email+")"};

  const {data:{session}} = await SB.auth.getSession();
  const {data,error:errPerfil} = await SB.from("usuarios").select("*").eq("user_id",session.user.id).maybeSingle();
  if(errPerfil) return {ok:false, detalle:"Leyendo usuarios: "+errPerfil.message};
  if(!data){
    await SB.auth.signOut();
    return {ok:false, detalle:"La contraseña es correcta, pero este usuario no está en la tabla `usuarios`. Falta correr el insert con user_id = "+session.user.id};
  }
  if(data.activo===false){
    await SB.auth.signOut();
    return {ok:false, detalle:"El usuario está marcado como inactivo en la tabla `usuarios`."};
  }
  _perfil = {nombre:data.nombre, usuarioId:data.id};
  return {ok:true, perfil:_perfil};
};

const getSess   = () => _perfil;
const clearSess = async () => { await SB.auth.signOut(); _perfil=null; };
const changeMyPassword = async newPass => {
  const {error} = await SB.auth.updateUser({password:newPass});
  return !error;
};

// Supabase no da error cuando una política de seguridad bloquea la fila: devuelve
// cero filas afectadas y listo. Este es el aviso para ese caso.
const SIN_PERMISO = "No se guardó: la base no permite modificar esta fila. Falta correr el SQL de permisos (8-corregir-desde-la-app.sql) en Supabase.";

// ── Mappers snake_case ↔ camelCase ────────────────────────────────────────────
const fromEvento = e => ({...e,maquinaId:e.maquina_id,resueltoFecha:e.resuelto_fecha,creadoPor:e.creado_por});
const fromEstado = e => ({...e,maquinaId:e.maquina_id,creadoPor:e.creado_por});
const toEvento   = e => ({maquina_id:e.maquinaId,tipo:e.tipo,descripcion:e.descripcion,fecha:e.fecha,resuelto:e.resuelto||false,resuelto_fecha:e.resueltoFecha||null,creado_por:e.creadoPor||""});

// ── CRUD Supabase ─────────────────────────────────────────────────────────────
const db = {
  // Máquinas + bitácora de eventos (rotura/repuesto/insumo)
  async loadAll() {
    const [mq,ev] = await Promise.all([
      SB.from("maquinas").select("*, plantas!inner(nombre, empresas!inner(nombre))").order("codigo"),
      SB.from("eventos_maquina").select("*").order("fecha",{ascending:false}),
    ]);
    const maquinas = (mq.data||[])
      .filter(m => m.plantas?.empresas?.nombre === EMPRESA)
      .map(m => ({id:m.id, codigo:m.codigo, nombre:m.nombre, activa:m.activa, notas:m.notas}));
    return { maquinas, eventos: (ev.data||[]).map(fromEvento) };
  },

  async saveMaquina(d, setMaqs) {
    const row={codigo:d.codigo,nombre:d.nombre||"",activa:d.activa!==false,notas:d.notas||""};
    await SB.from("maquinas").update(row).eq("id",d.id);
    setMaqs(prev=>prev.map(m=>m.id===d.id?{...m,...row}:m));
  },

  // Alta manual (la RPC resuelve empresa/planta sola)
  async crearMaquina(codigo, nombre) {
    const {error} = await SB.rpc("crear_maquina",{_codigo:codigo,_nombre:nombre||""});
    return !error ? {ok:true} : {ok:false, detalle:error.message};
  },

  async delMaquina(id, setMaqs) {
    const {error} = await SB.from("maquinas").delete().eq("id",id);
    if(error) return {ok:false, detalle:error.message};
    if(setMaqs) setMaqs(prev=>prev.filter(m=>m.id!==id));
    return {ok:true};
  },

  async saveEvento(d, setEventos) {
    const {data} = await SB.from("eventos_maquina").insert(toEvento(d)).select().single();
    if(data) setEventos(prev=>[fromEvento(data),...prev]);
  },

  async marcarResuelto(id, resuelto, setEventos) {
    const resuelto_fecha = resuelto ? hoyIso() : null;
    await SB.from("eventos_maquina").update({resuelto,resuelto_fecha}).eq("id",id);
    setEventos(prev=>prev.map(e=>e.id===id?{...e,resuelto,resueltoFecha:resuelto_fecha}:e));
  },

  async delEvento(id, setEventos) {
    await SB.from("eventos_maquina").delete().eq("id",id);
    setEventos(prev=>prev.filter(e=>e.id!==id));
  },

  // Monitoreo en vivo: qué está haciendo cada máquina ahora
  async loadEstadoActual() {
    const {data} = await SB.from("v_estado_actual").select("*").order("maquina");
    return (data||[]).map(fromEstado);
  },

  // Cierra el tramo anterior y abre uno nuevo (RPC, en una sola operación)
  async cambiarEstado({maquinaId,estado,medida,presentacion,motivo,creadoPor}) {
    const {error} = await SB.rpc("cambiar_estado_maquina",{
      _maquina_id:maquinaId, _estado:estado,
      _medida:medida||"", _presentacion:presentacion||"",
      _motivo:motivo||"", _creado_por:creadoPor||""
    });
    return !error ? {ok:true} : {ok:false, detalle:error.message};
  },

  // Historial de tramos de una máquina (lo último primero)
  async historialEstados(maquinaId) {
    const {data} = await SB.from("estados_maquina").select("*")
      .eq("maquina_id",maquinaId).order("inicio",{ascending:false}).limit(100);
    return (data||[]).map(fromEstado);
  },

  // Manda la foto al formulario de n8n. Campos, en el orden del formulario:
  // field-0 la foto, field-1 rollera, field-2 planta, field-3 fecha y field-4 turno
  // (solo si se forzaron a mano), field-5 el código de esta carga.
  // Con ese código la app después pregunta qué pasó con ESTA foto.
  async subirFoto(archivo, maquina, fecha, turno, cargaId) {
    const fd = new FormData();
    fd.append("field-0", archivo, archivo.name || "hoja.jpg");
    fd.append("field-1", maquina || "");
    fd.append("field-2", "Rolleras");
    fd.append("field-3", fecha || "");
    fd.append("field-4", turno || "");
    fd.append("field-5", cargaId || "");
    try {
      const r = await fetch(N8N_FORM_URL, { method:"POST", body: fd });
      if(!r.ok) return {ok:false, detalle:"n8n respondió "+r.status+". ¿El workflow está activo?"};
      return {ok:true};
    } catch(e) {
      return {ok:false, detalle:"No se pudo conectar con n8n: "+e.message};
    }
  },

  // Qué pasó con una carga: nueva, ya_cargada, nueva_mismo_turno o fallida.
  // Si la base todavía no tiene la función (falta el SQL 13) devuelve sinSoporte.
  async estadoCarga(cargaId) {
    const {data,error} = await SB.rpc("estado_carga",{_carga_id:cargaId});
    if(error) return {sinSoporte:true};
    return {dato:data||null};
  },

  async cargasRecientes(limite) {
    const {data,error} = await SB.rpc("cargas_recientes",{_limite:limite||15});
    if(error) return null;
    return data||[];
  },

  // Los id de las hojas que hay ahora. Comparando la lista antes y después de
  // subir se identifica exactamente cuál es la nueva. (Antes se tomaba "la de
  // fecha más alta", y con una hoja mal fechada en el futuro siempre ganaba esa.)
  async idsDePartes() {
    const {data} = await SB.from("v_producciones").select("id").eq("empresa",EMPRESA);
    return new Set((data||[]).map(p=>p.id));
  },

  async parteporId(id) {
    const {data} = await SB.from("v_producciones").select("*").eq("id",id).limit(1);
    return (data||[])[0] || null;
  },

  // Carga manual de una hoja de control (misma RPC que usa n8n con las fotos:
  // evita bobinas duplicadas y crea máquina/operario si no existen).
  async cargarParte(parte) {
    const datos = {
      empresa: EMPRESA,
      planta: "Rolleras",
      rollera: parte.rollera,                       // la máquina de la planta que cortó
      maquina_origen: parte.maquinaOrigen || "",    // la extrusora que hizo la bobina
      operario: parte.operario || "",
      fecha: parte.fecha,
      turno: parte.turno,
      medida: parte.medida || "",
      filas: parte.filas || null,
      bultos: parte.bultos || null,
      observaciones: parte.observaciones || "",
      scrap_empalme: Number(parte.scrapEmpalme) || 0,
      scrap_rollo: Number(parte.scrapRollo) || 0,
      origen: "carga manual",
      bobinas: parte.bobinas.map(b=>({
        n_bobina: String(b.n).trim(),
        peso: Number(b.peso) || null,
        iniciales: (b.iniciales||"").toUpperCase().trim(),
        estado: b.estado || null,
        defecto: (b.defecto||"").trim()
      }))
    };
    const {data,error} = await SB.rpc("cargar_parte",{datos});
    if(error) return {ok:false, detalle:error.message};
    return {ok:true, resultado:data};
  },

  // ── Correcciones: cuando la IA lee mal una fecha, un peso o un estado ──
  async bobinasDeHoja(produccionId) {
    const {data} = await SB.from("v_bobinas").select("*")
      .eq("produccion_id",produccionId).order("n_bobina");
    return data||[];
  },

  // Ojo: si una política de seguridad bloquea la fila, Supabase no devuelve error,
  // simplemente no actualiza nada. Por eso se pide de vuelta la fila y se controla
  // que realmente haya cambiado algo.
  async actualizarHoja(id, campos) {
    const {data,error} = await SB.from("producciones").update({
      fecha: campos.fecha,
      turno: campos.turno,
      medida: campos.medida||"",
      bultos: campos.bultos===""||campos.bultos==null ? null : Number(campos.bultos),
      observaciones: campos.observaciones||"",
      maquina_origen: campos.maquinaOrigen||""
    }).eq("id",id).select();
    if(error) return {ok:false, detalle:error.message};
    if(!data || data.length===0) return {ok:false, detalle:SIN_PERMISO};
    return {ok:true};
  },

  // El scrap está en otra tabla (una fila por hoja): se crea o se actualiza.
  async actualizarScrap(produccionId, empalme, rollo) {
    const {data,error} = await SB.from("scrap").upsert({
      produccion_id: produccionId,
      empalme: empalme===""||empalme==null ? 0 : Number(empalme),
      rollo: rollo===""||rollo==null ? 0 : Number(rollo)
    },{onConflict:"produccion_id"}).select();
    if(error) return {ok:false, detalle:error.message};
    if(!data || data.length===0) return {ok:false, detalle:SIN_PERMISO};
    return {ok:true};
  },

  async borrarHoja(id) {
    // Las bobinas y el scrap se borran solos (on delete cascade).
    const {data,error} = await SB.from("producciones").delete().eq("id",id).select();
    if(error) return {ok:false, detalle:error.message};
    if(!data || data.length===0) return {ok:false, detalle:SIN_PERMISO};
    return {ok:true};
  },

  async actualizarBobina(id, campos) {
    const {data,error} = await SB.from("bobinas").update({
      n_bobina: String(campos.n||"").trim(),
      peso: campos.peso===""||campos.peso==null ? null : Number(campos.peso),
      iniciales: (campos.iniciales||"").toUpperCase().trim(),
      estado: campos.estado||null
    }).eq("id",id).select();
    if(error) return {ok:false, detalle:error.message};
    if(!data || data.length===0) return {ok:false, detalle:SIN_PERMISO};
    return {ok:true};
  },

  async borrarBobina(id) {
    const {data,error} = await SB.from("bobinas").delete().eq("id",id).select();
    if(error) return {ok:false, detalle:error.message};
    if(!data || data.length===0) return {ok:false, detalle:SIN_PERMISO};
    return {ok:true};
  },

  // Estadísticas de producción (hojas de control ya cargadas por foto → Gemini)
  async loadProduccion(desde, hasta) {
    const [b,p] = await Promise.all([
      SB.from("v_bobinas").select("*").eq("empresa",EMPRESA).gte("fecha",desde).lte("fecha",hasta).order("fecha",{ascending:false}).limit(20000),
      SB.from("v_producciones").select("*").eq("empresa",EMPRESA).gte("fecha",desde).lte("fecha",hasta).order("fecha",{ascending:false}).limit(5000),
    ]);
    return { bobinas: b.data||[], producciones: p.data||[] };
  },
};

// ── Constantes de datos ───────────────────────────────────────────────────────
const TIPOS_EVENTO = [
  {id:"rotura",label:"Rotura / Falla",icon:"🔴",color:RE},
  {id:"repuesto",label:"Falta repuesto",icon:"🔧",color:O},
  {id:"insumo",label:"Falta insumo",icon:"🧴",color:BL},
];
const tipoInfo = id => TIPOS_EVENTO.find(t=>t.id===id) || TIPOS_EVENTO[0];

// Estados de monitoreo en vivo
const ESTADOS = [
  {id:"produciendo",label:"Produciendo",icon:"🟢",color:GN},
  {id:"parada",label:"Parada",icon:"🟡",color:O},
  {id:"apagada",label:"Apagada",icon:"⚫",color:GR},
];
const estadoInfo = id => ESTADOS.find(e=>e.id===id) || null;

// Motivos típicos de parada (se puede escribir cualquier otro)
const MOTIVOS_PARADA = ["Cambio de cinta","Cambio de medida","Repuesto","Mantenimiento","Sin material","Fin de turno"];

// "hace 3 h 20 min" a partir de un timestamp
const desdeHace = iso => {
  if(!iso) return "";
  const min = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime())/60000));
  if(min < 60) return "hace "+min+" min";
  const h = Math.floor(min/60), m = min%60;
  if(h < 24) return "hace "+h+" h"+(m?" "+m+" min":"");
  const d = Math.floor(h/24);
  return "hace "+d+" día"+(d!==1?"s":"")+(h%24?" "+(h%24)+" h":"");
};

// El código suele ser solo el número ("5" → "Rollera 5"), pero si ya viene con
// texto ("rollera 5", "R5") se respeta tal cual y se muestra capitalizado.
const tituloMaquina = codigo => {
  const c = String(codigo||"").trim();
  if(!c) return "Máquina";
  if(/^\d+$/.test(c)) return "Rollera "+c;
  return c.charAt(0).toUpperCase()+c.slice(1);
};

// ── Rollos y bolsas por turno ────────────────────────────────────────────────
// La medida dice todo: "45x60x20x24" = bolsa de 45x60, 20 bolsas por rollo y
// 24 rollos por bulto. Si hay dos productos ("80x110x10x50 / 60x90x10x24") se usa
// el primero. Si falta un número, ese dato se escribe a mano.
const numerosMedida = medida => (String(medida||"").split(/[\/,]/)[0].match(/\d+/g) || []).map(Number);
const bolsasPorRollo = medida => { const n = numerosMedida(medida); return n.length >= 3 ? n[2] : null; };
const rollosPorBulto = medida => { const n = numerosMedida(medida); return n.length >= 4 ? n[3] : null; };
// Los millares son de BOLSAS (unidades). Los registros viejos sin el dato de
// bolsas se calculan con la medida que se guardó.
const bolsasDe = r => r.bolsas != null ? Number(r.bolsas) : (Number(r.rollos)||0) * (bolsasPorRollo(r.medida)||0);
const millares = n => ((Number(n)||0)/1000).toLocaleString("es-AR",{maximumFractionDigits:1});

const dbRollos = {
  async listar(desde, hasta) {
    const {data,error} = await SB.from("v_rollos").select("*").eq("empresa",EMPRESA)
      .gte("fecha",desde).lte("fecha",hasta)
      .order("fecha",{ascending:false}).order("creado_en",{ascending:false}).limit(3000);
    if(error) return null;   // falta el SQL 16
    return data||[];
  },
  async guardar(f) {
    const {data,error} = await SB.from("rollos_turno").insert({
      maquina_id: f.maquinaId, fecha: f.fecha, turno: f.turno, medida: f.medida||"",
      bultos: Number(f.bultos), rollos_por_bulto: Number(f.rollosPorBulto), rollos: Number(f.rollos),
      bolsas_por_rollo: f.bolsasPorRollo ? Number(f.bolsasPorRollo) : null,
      bolsas: f.bolsas != null ? Number(f.bolsas) : null,
      creado_por: f.creadoPor||""
    }).select();
    if(error) return {ok:false, detalle: /bolsas/.test(error.message)
      ? "Falta correr el SQL 17 (bolsas) en Supabase."
      : /rollos_turno|42P01/.test(error.message+error.code)
      ? "Falta correr el SQL 16 (rollos) en Supabase." : error.message};
    if(!data || data.length===0) return {ok:false, detalle:SIN_PERMISO};
    return {ok:true};
  },
  async borrar(id) {
    const {data,error} = await SB.from("rollos_turno").delete().eq("id",id).select();
    if(error) return {ok:false, detalle:error.message};
    if(!data || data.length===0) return {ok:false, detalle:SIN_PERMISO};
    return {ok:true};
  },
};

// ── Quitar una nota de revisión ya resuelta ──────────────────────────────────
// Las observaciones son "texto de la hoja | ⚠ REVISAR: motivo 1 | motivo 2".
// Saca el motivo que coincide con `patron` y deja el resto igual; si el que se
// saca era el que llevaba la marca "⚠ REVISAR:", la marca pasa al siguiente.
const quitarNotaRevisar = (obs, patron) => {
  const MARCA = "⚠ REVISAR:";
  const out = [];
  let enRevisar = false, marcaPendiente = false;
  for (const parte of String(obs||"").split(" | ")) {
    let texto = parte;
    if (parte.startsWith(MARCA)) { enRevisar = true; marcaPendiente = true; texto = parte.slice(MARCA.length).trim(); }
    if (enRevisar && patron.test(texto)) continue;
    if (enRevisar && marcaPendiente) { out.push(MARCA + " " + texto); marcaPendiente = false; }
    else out.push(texto);
  }
  return out.filter(p => p.trim() !== "").join(" | ");
};

// ── Hojas para revisar ───────────────────────────────────────────────────────
// Se calcula en el momento con los datos reales: cuando se corrige, la marca
// desaparece sola. Rangos tomados de lo que es normal en la planta (mediana 10
// bobinas y ~480.000 kg por hoja; bobinas de 40.000 a 57.000 kg).
const normBobina = n => String(n||"").toUpperCase().replace(/[^0-9A-Z]/g,"");
const problemasHoja = (p, bobinasDeLaHoja) => {
  const out = [];
  const bs = bobinasDeLaHoja || [];
  // 120 días: una hoja de hace 2 meses es normal; las de años anteriores no.
  if (p.fecha > hoyIso()) out.push("Fecha futura ("+fdate(p.fecha)+")");
  else if (p.fecha < haceDiasIso(120)) out.push("Fecha de hace más de 4 meses ("+fdate(p.fecha)+"): probablemente el año o el mes mal leído");
  if (bs.length > 20) out.push("Tiene "+bs.length+" bobinas, el doble de lo normal: puede haber otra hoja mezclada o la misma foto cargada más de una vez");
  else if ((+p.kilos||0) > 1000000) out.push(fnum(p.kilos)+" kg en un turno es mucho más de lo normal");
  const raros = bs.filter(b => b.peso!=null && (+b.peso < 20000 || +b.peso > 80000));
  if (raros.length) out.push("Peso raro en "+raros.map(b=>"bobina "+b.n_bobina+" ("+fnum(b.peso)+" kg)").join(", "));
  const sinPeso = bs.filter(b => b.peso==null);
  if (sinPeso.length) out.push("Sin peso: bobina "+sinPeso.map(b=>b.n_bobina).join(", "));
  const porNum = {};
  bs.forEach(b => (porNum[normBobina(b.n_bobina)] = porNum[normBobina(b.n_bobina)] || []).push(b));
  const rep = Object.values(porNum).filter(l => l.length > 1);
  if (rep.length) out.push("Número repetido: "+rep.map(l => l[0].n_bobina+" ("+l.map(b=>fnum(b.peso)).join(" y ")+" kg)").join(", ")+". Si es la misma bobina, borrá una");
  const sinEstado = bs.filter(b => !b.estado).length;
  if (sinEstado) out.push(sinEstado+(sinEstado===1?" bobina sin":" bobinas sin")+" BIEN/MAL");
  const scrap = (+p.scrap_empalme||0) + (+p.scrap_rollo||0);
  if (p.kilos && scrap/p.kilos > 0.05) out.push("Scrap de "+(100*scrap/p.kilos).toFixed(1)+"%, muy alto");
  const obs = p.observaciones||"";
  if (obs.includes("⚠ REVISAR:")) out.push(obs.split("⚠ REVISAR:")[1].trim());
  return out;
};

// "lun 4/8 06:30"
const fhora = iso => {
  if(!iso) return "";
  const d = new Date(iso);
  const dia = ["dom","lun","mar","mié","jue","vie","sáb"][d.getDay()];
  return dia+" "+d.getDate()+"/"+(d.getMonth()+1)+" "+String(d.getHours()).padStart(2,"0")+":"+String(d.getMinutes()).padStart(2,"0");
};
