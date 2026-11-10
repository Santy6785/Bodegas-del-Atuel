/**
 * Bodegas del Atuel - Validador de fixtures contra el contrato de la API.
 *
 * Script de Node sin dependencias. Valida front/js/fixtures/catalogo.js contra
 * docs/api-contrato.md (sección 4.1 Vinos y sección 4.7 Catálogos auxiliares).
 *
 * Uso: node front/scripts/validar-fixtures.mjs
 */

import {
  listaVinosFixture,
  detallesVinoFixture,
  cepasFixture,
  bodegasFixture,
} from "../js/fixtures/catalogo.js";

let errores = 0;
let exitos = 0;

function check(condicion, mensaje) {
  if (condicion) {
    exitos++;
    console.log(`  ✔ ${mensaje}`);
  } else {
    errores++;
    console.error(`  ✘ ${mensaje}`);
  }
}

const CLAVES_ITEM = [
  "cod_vino",
  "nombre",
  "tipo",
  "anada",
  "volumen_ml",
  "graduacion",
  "precio",
  "cuit_bodega",
  "bodega_razon_social",
];
const TIPOS_VALIDOS = ["tinto", "blanco", "rosado", "espumante"];
const REGEX_DECIMAL = /^\d+\.\d{2}$/;
const REGEX_CUIT = /^\d{11}$/;

console.log("=== Validación de fixtures vs contrato API ===\n");

// --- 1. Estructura de listaVinosFixture ---
console.log("1. listaVinosFixture");
check(
  listaVinosFixture && typeof listaVinosFixture === "object",
  "listaVinosFixture es un objeto"
);
check(
  Array.isArray(listaVinosFixture.items),
  "items es un arreglo"
);
check(
  listaVinosFixture.items.length >= 6,
  `tiene al menos 6 vinos (${listaVinosFixture.items.length})`
);
check(
  typeof listaVinosFixture.page === "number",
  "page es número"
);
check(
  typeof listaVinosFixture.page_size === "number",
  "page_size es número"
);
check(
  typeof listaVinosFixture.total === "number",
  "total es número"
);
check(
  listaVinosFixture.total === listaVinosFixture.items.length,
  `total (${listaVinosFixture.total}) === cantidad de items (${listaVinosFixture.items.length})`
);

const tiposPresentes = new Set();
const bodegasPresentes = new Set();

listaVinosFixture.items.forEach((item, i) => {
  const claves = Object.keys(item).sort();
  const clavesEsperadas = [...CLAVES_ITEM].sort();
  check(
    JSON.stringify(claves) === JSON.stringify(clavesEsperadas),
    `ítem ${i} (cod_vino=${item.cod_vino}): claves exactas del contrato`
  );
  check(
    Number.isInteger(item.cod_vino),
    `ítem ${i}: cod_vino entero (${item.cod_vino})`
  );
  check(
    typeof item.nombre === "string" && item.nombre.length > 0,
    `ítem ${i}: nombre string no vacío`
  );
  check(
    TIPOS_VALIDOS.includes(item.tipo),
    `ítem ${i}: tipo válido "${item.tipo}"`
  );
  tiposPresentes.add(item.tipo);
  check(
    Number.isInteger(item.anada),
    `ítem ${i}: anada entero (${item.anada})`
  );
  check(
    Number.isInteger(item.volumen_ml),
    `ítem ${i}: volumen_ml entero (${item.volumen_ml})`
  );
  check(
    typeof item.graduacion === "string" && REGEX_DECIMAL.test(item.graduacion),
    `ítem ${i}: graduacion string decimal "${item.graduacion}"`
  );
  check(
    typeof item.precio === "string" && REGEX_DECIMAL.test(item.precio),
    `ítem ${i}: precio string decimal "${item.precio}"`
  );
  check(
    typeof item.cuit_bodega === "string" && REGEX_CUIT.test(item.cuit_bodega),
    `ítem ${i}: cuit_bodega 11 dígitos "${item.cuit_bodega}"`
  );
  check(
    typeof item.bodega_razon_social === "string" && item.bodega_razon_social.length > 0,
    `ítem ${i}: bodega_razon_social string no vacío`
  );
  bodegasPresentes.add(item.cuit_bodega);
});

check(
  tiposPresentes.size >= 4,
  `incluye los 4 tipos de vino (${[...tiposPresentes].join(", ")})`
);
check(
  TIPOS_VALIDOS.every((t) => tiposPresentes.has(t)),
  "contiene tinto, blanco, rosado y espumante"
);
check(
  bodegasPresentes.size >= 2,
  `al menos 2 bodegas (${bodegasPresentes.size})`
);

// --- 2. detallesVinoFixture ---
console.log("\n2. detallesVinoFixture");
check(
  detallesVinoFixture && typeof detallesVinoFixture === "object",
  "detallesVinoFixture es un objeto indexado por cod_vino"
);

const codigosEsperados = new Set(
  listaVinosFixture.items.map((i) => i.cod_vino)
);
const codigosPresentes = new Set(
  Object.keys(detallesVinoFixture).map(Number)
);

check(
  [...codigosEsperados].every((c) => detallesVinoFixture[c] !== undefined),
  "tiene detalle para cada vino del listado"
);

Object.entries(detallesVinoFixture).forEach(([codStr, detalle]) => {
  const cod = Number(codStr);
  const item = listaVinosFixture.items.find((i) => i.cod_vino === cod);

  check(
    detalle.cod_vino === cod,
    `detalle ${cod}: cod_vino coincide`
  );
  check(
    detalle.bodega && typeof detalle.bodega === "object",
    `detalle ${cod}: tiene objeto bodega`
  );
  check(
    detalle.bodega.cuit === item.cuit_bodega,
    `detalle ${cod}: bodega.cuit === cuit_bodega del ítem`
  );
  check(
    detalle.bodega.razon_social === item.bodega_razon_social,
    `detalle ${cod}: bodega.razon_social === bodega_razon_social del ítem`
  );

  // Composición: porcentajes suman 100
  const composicion = detalle.composicion || [];
  check(
    Array.isArray(composicion) && composicion.length > 0,
    `detalle ${cod}: composicion es arreglo no vacío`
  );
  if (Array.isArray(composicion)) {
    const suma = composicion.reduce((acc, c) => acc + Number(c.porcentaje), 0);
    check(
      Math.abs(suma - 100) < 0.01,
      `detalle ${cod}: composición suma 100 (suma=${suma})`
    );
    composicion.forEach((c) => {
      check(
        ["tinta", "blanca"].includes(c.tipo),
        `detalle ${cod}: cepa ${c.nombre} tipo válido "${c.tipo}"`
      );
      check(
        typeof c.porcentaje === "string" && REGEX_DECIMAL.test(c.porcentaje),
        `detalle ${cod}: porcentaje string decimal "${c.porcentaje}"`
      );
    });
  }

  // Maridajes
  const maridajes = detalle.maridajes || [];
  check(
    Array.isArray(maridajes),
    `detalle ${cod}: maridajes es arreglo`
  );
  maridajes.forEach((m) => {
    check(
      typeof m.temperatura_servicio === "number",
      `detalle ${cod}: maridaje ${m.nombre} temperatura_servicio número`
    );
  });

  // Stock
  const stock = detalle.stock || {};
  check(
    Number.isInteger(stock.deposito),
    `detalle ${cod}: stock.deposito entero`
  );
  check(
    Number.isInteger(stock.salas),
    `detalle ${cod}: stock.salas entero`
  );
  check(
    Number.isInteger(stock.total),
    `detalle ${cod}: stock.total entero`
  );
  check(
    stock.total === stock.deposito + stock.salas,
    `detalle ${cod}: stock.total === deposito + salas (${stock.total} = ${stock.deposito} + ${stock.salas})`
  );
});

// --- 3. cepasFixture ---
console.log("\n3. cepasFixture");
check(
  Array.isArray(cepasFixture),
  "cepasFixture es un arreglo"
);
cepasFixture.forEach((c) => {
  check(
    Number.isInteger(c.id_cepa),
    `cepa ${c.nombre}: id_cepa entero`
  );
  check(
    typeof c.nombre === "string" && c.nombre.length > 0,
    `cepa ${c.nombre}: nombre string`
  );
  check(
    ["tinta", "blanca"].includes(c.tipo),
    `cepa ${c.nombre}: tipo válido "${c.tipo}"`
  );
});

// --- 4. bodegasFixture ---
console.log("\n4. bodegasFixture");
check(
  Array.isArray(bodegasFixture),
  "bodegasFixture es un arreglo"
);
bodegasFixture.forEach((b) => {
  check(
    typeof b.cuit === "string" && REGEX_CUIT.test(b.cuit),
    `bodega ${b.razon_social}: cuit 11 dígitos`
  );
  check(
    typeof b.razon_social === "string" && b.razon_social.length > 0,
    `bodega ${b.razon_social}: razon_social string`
  );
  check(
    typeof b.domicilio === "string" && b.domicilio.length > 0,
    `bodega ${b.razon_social}: domicilio string`
  );
});

// --- Resumen ---
console.log("\n=== Resumen ===");
console.log(`Éxitos: ${exitos}`);
console.log(`Errores: ${errores}`);

if (errores > 0) {
  console.error("VALIDACIÓN FALLÓ");
  process.exit(1);
} else {
  console.log("VALIDACIÓN SUPERADA");
  process.exit(0);
}
