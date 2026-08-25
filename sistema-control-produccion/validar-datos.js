// Validaciones automaticas: nunca se guarda nada inventado.
// errores  -> bloquean la carga
// advertencias -> se guarda igual pero se avisa que revisar
//
// La IA no siempre devuelve la misma estructura: a veces manda los campos en el
// primer nivel y a veces anidados en "cabecera" / "tabla_bobinas". Y los numeros
// pueden venir con puntos de miles ("44.000") y las fechas en formato argentino
// ("11/8/26" = 11 de agosto). Todo eso se normaliza aca.
const salida = $input.first().json;
let textoIA = salida.content?.parts?.[0]?.text ?? salida.text ?? '';
const limpio = textoIA.replace(/```json/gi, '').replace(/```/g, '').trim();
let bruto;
try {
  bruto = JSON.parse(limpio);
} catch (e) {
  throw new Error('La IA no devolvio un JSON valido: ' + textoIA.substring(0, 300));
}

const prep = $('Preparar').first().json;
const errores = [];
const adv = [];
const esIlegible = v => typeof v === 'string' && v.toUpperCase().includes('ILEGIBLE');

// --- normalizar la forma de la respuesta ---
const cab = bruto.cabecera || bruto.encabezado || bruto;
const filas = bruto.bobinas || bruto.tabla_bobinas || bruto.tablaBobinas || cab.bobinas || [];
const d = {
  maquina: cab.maquina,
  fecha: cab.fecha,
  turno: cab.turno,
  operario: cab.operario,
  medida: cab.medida ?? bruto.medida,
  filas: cab.filas ?? bruto.filas,
  bultos: cab.bultos ?? bruto.bultos,
  observaciones: cab.observaciones ?? bruto.observaciones,
  scrap_empalme: cab.scrap_empalme ?? bruto.scrap_empalme,
  scrap_rollo: cab.scrap_rollo ?? bruto.scrap_rollo
};

// "44.000" / "44,000" / "44 000" -> 44000
const aNumero = v => {
  if (v == null) return NaN;
  if (typeof v === 'number') return v;
  const s = String(v).replace(/[^\d]/g, '');
  return s === '' ? NaN : Number(s);
};

// Acepta "2026-08-11" y tambien "11/8/26" o "11-08-2026" (dia/mes/anio, como se
// escribe en Argentina). Nunca interpreta el primer numero como mes.
const aFechaISO = v => {
  if (!v || esIlegible(v)) return null;
  const s = String(v).trim();
  let m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return m[1] + '-' + m[2] + '-' + m[3];
  m = s.match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})$/);
  if (m) {
    const dia = m[1].padStart(2, '0');
    const mes = m[2].padStart(2, '0');
    let anio = m[3];
    if (anio.length === 2) anio = '20' + anio;
    if (Number(mes) < 1 || Number(mes) > 12 || Number(dia) < 1 || Number(dia) > 31) return null;
    return anio + '-' + mes + '-' + dia;
  }
  return null;
};

// Cuantos dias hace (negativo = esta en el futuro)
const diasAtras = iso => (Date.now() - new Date(iso + 'T00:00:00').getTime()) / 86400000;

// La IA lee bien el dia y el mes, pero el anio escrito a mano ("26") lo confunde
// con 20, 21 o 24. Como las hojas de control son siempre de los ultimos dias, si
// el anio leido no da una fecha razonable se prueba con el actual y el anterior.
const corregirAnio = iso => {
  if (!iso) return { fecha: iso, corregido: false };
  const partes = iso.split('-');
  const mes = partes[1], dia = partes[2];
  const hoy = new Date();
  if (diasAtras(iso) >= -2 && diasAtras(iso) <= 400) return { fecha: iso, corregido: false };
  for (const anio of [hoy.getFullYear(), hoy.getFullYear() - 1]) {
    const prueba = anio + '-' + mes + '-' + dia;
    if (isNaN(new Date(prueba + 'T00:00:00').getTime())) continue;
    const dias = diasAtras(prueba);
    if (dias >= -2 && dias <= 150) return { fecha: prueba, corregido: true, antes: iso };
  }
  return { fecha: iso, corregido: false };
};

// --- fecha ---
// Si la persona la forzo desde la app (letra ilegible), esa manda.
let fecha = aFechaISO(prep.fecha_forzada) || null;
if (fecha) {
  adv.push('Fecha puesta a mano desde la app: ' + fecha);
} else {
  fecha = aFechaISO(d.fecha);
  if (fecha) {
    const r = corregirAnio(fecha);
    if (r.corregido) {
      adv.push('El anio leido (' + r.antes + ') no era posible: se corrigio a ' + r.fecha + '. Verificar.');
      fecha = r.fecha;
    }
  }
}
// Si no se pudo leer, NO se descarta la hoja: se guarda con la fecha de hoy y se
// marca para revisar. Es preferible tener los pesos con la fecha a corregir que
// perder la hoja entera.
if (!fecha || isNaN(new Date(fecha + 'T00:00:00').getTime())) {
  const h = new Date();
  fecha = h.getFullYear() + '-' + String(h.getMonth() + 1).padStart(2, '0') + '-' + String(h.getDate()).padStart(2, '0');
  adv.push('FECHA NO LEIDA: se guardo con la fecha de hoy (' + fecha + '). Corregirla en la app.');
} else {
  const dias = diasAtras(fecha);
  if (dias < -1) adv.push('La fecha es futura (' + fecha + '): verificar');
  if (dias > 60) adv.push('La fecha tiene mas de 60 dias (' + fecha + '): verificar');
}

// --- turno ---
let turno = String(prep.turno_forzado || d.turno || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
if (turno.startsWith('dia')) turno = 'dia';
else if (turno.startsWith('noche')) turno = 'noche';
else {
  adv.push('Turno sin marcar o ilegible: se guarda como "dia", verificar');
  turno = 'dia';
}

// --- operario ---
let operario = (!d.operario || esIlegible(d.operario)) ? '' : String(d.operario).trim();
if (!operario) adv.push('Operario faltante o ilegible');

// --- rollera y maquina de origen ---
// La ROLLERA la elige la persona al subir la hoja. La maquina que figura escrita
// en la hoja es la que fabrico la bobina, y se guarda solo como trazabilidad.
// Si no vino la rollera se guarda igual, bajo "S/D", para no perder los pesos.
let rollera = String(prep.maquina_hint || '').trim();
if (!rollera) {
  rollera = 'S/D';
  adv.push('ROLLERA NO INDICADA: se guardo como S/D. Corregirla en la app.');
}

let maquina_origen = (d.maquina && !esIlegible(d.maquina)) ? String(d.maquina).trim() : '';
if (!maquina_origen) adv.push('Maquina de origen de la bobina faltante o ilegible');

// --- bobinas ---
const vistas = new Set();
const bobinas = [];
for (const b of (Array.isArray(filas) ? filas : [])) {
  // El numero puede venir entero ("1-52") o partido en dos campos.
  let n = b.n_bobina ?? b.numero ?? b.n ?? '';
  if (!n && (b.numero_m != null || b.numero_b != null)) {
    n = String(b.numero_m ?? '').trim() + String(b.numero_b ?? '').trim();
  }
  n = esIlegible(n) ? '' : String(n).replace(/\s+/g, '').trim();
  if (!n) { adv.push('Una bobina no tiene numero legible: se omitio'); continue; }

  const peso = aNumero(b.peso);
  if (isNaN(peso)) {
    adv.push('Bobina ' + n + ': peso faltante o ilegible');
  } else if (peso < 10000 || peso > 100000) {
    adv.push('Bobina ' + n + ': peso fuera del rango habitual (' + peso + '), verificar');
  }

  let estado = String(b.estado || '').toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
  if (estado !== 'BIEN' && estado !== 'MAL') {
    estado = null;
    adv.push('Bobina ' + n + ': estado BIEN/MAL sin marcar o ilegible');
  }

  // Los defectos pueden venir como texto o como lista.
  let defecto = b.defecto ?? b.defectos ?? '';
  if (Array.isArray(defecto)) defecto = defecto.filter(Boolean).join(', ');
  defecto = esIlegible(defecto) ? '' : String(defecto).trim();

  // La misma numeracion se puede repetir (bobinas viejas y nuevas de la misma
  // maquina), asi que solo se descarta si es identica en numero Y peso.
  const clave = n + '|' + (isNaN(peso) ? '' : peso);
  if (vistas.has(clave)) { adv.push('Bobina ' + n + ': repetida identica en la hoja, se omitio'); continue; }
  vistas.add(clave);

  bobinas.push({
    n_bobina: n,
    peso: isNaN(peso) ? null : peso,
    iniciales: (b.iniciales && !esIlegible(b.iniciales)) ? String(b.iniciales).toUpperCase().trim() : '',
    estado,
    defecto
  });
}
if (bobinas.length === 0) errores.push('No se pudo leer ninguna bobina de la hoja');

// --- scrap ---
const se = aNumero(d.scrap_empalme);
const sr = aNumero(d.scrap_rollo);
if (isNaN(se)) adv.push('Scrap de empalme faltante o ilegible (se guarda 0)');
if (isNaN(sr)) adv.push('Scrap de rollo faltante o ilegible (se guarda 0)');

// Lo que la IA no pudo leer queda escrito en la propia hoja, para que se vea en
// la app y se sepa que hay que revisar (y que fue lo que fallo).
const obsHoja = (d.observaciones && !esIlegible(d.observaciones)) ? String(d.observaciones).trim() : '';
const aRevisar = adv.filter(a => /NO LEIDA|NO INDICADA|se corrigio|futura|mas de 60 dias|ilegible|sin marcar/i.test(a));
const observaciones = aRevisar.length
  ? (obsHoja ? obsHoja + ' | ' : '') + '⚠ REVISAR: ' + aRevisar.join(' | ')
  : obsHoja;

const datos = {
  empresa: 'Coop El Circulo',
  planta: prep.planta || 'Rolleras',
  rollera, maquina_origen, operario, fecha, turno, bobinas,
  scrap_empalme: isNaN(se) ? 0 : se,
  scrap_rollo: isNaN(sr) ? 0 : sr,
  medida: (d.medida && !esIlegible(d.medida)) ? String(d.medida) : '',
  filas: aNumero(d.filas) || null,
  bultos: aNumero(d.bultos) || null,
  observaciones,
  origen: prep.origen
};

return [{ json: { datos, errores, advertencias: adv, chat_id: prep.chat_id } }];
