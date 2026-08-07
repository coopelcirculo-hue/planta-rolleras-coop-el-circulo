// ── Supabase ──────────────────────────────────────────────────────────────────
const SB = window.supabase.createClient(
  "https://yequwsdaqbihkmjtyuvm.supabase.co",
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InllcXV3c2RhcWJpaGttanR5dXZtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Nzk1MTcsImV4cCI6MjEwMTQ1NTUxN30.6M_UMFBvd3thFlDEwiZZwjXkAAGxXnE-IUFYsS1Xcj0"
);
const SUPABASE_CONFIGURADO = true;

// Nombre de empresa usado en el esquema multi-empresa (debe coincidir con lo que
// manda el flujo de ingesta de n8n en el campo "empresa" de cada hoja de control).
const EMPRESA = "Coop El Circulo";

// ── Colores ───────────────────────────────────────────────────────────────────
const O="#f59e0b",D="#111827",CA="#1a2232",CB="#1F2937",BR="#2d3748",GR="#9CA3AF",W="#F8FAFC",RE="#ef4444",GN="#22c55e",BL="#60a5fa",PU="#a78bfa";

// ── Helpers ───────────────────────────────────────────────────────────────────
const fdate = d => new Date(d).toLocaleDateString("es-AR");
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

// "lun 4/8 06:30"
const fhora = iso => {
  if(!iso) return "";
  const d = new Date(iso);
  const dia = ["dom","lun","mar","mié","jue","vie","sáb"][d.getDay()];
  return dia+" "+d.getDate()+"/"+(d.getMonth()+1)+" "+String(d.getHours()).padStart(2,"0")+":"+String(d.getMinutes()).padStart(2,"0");
};
