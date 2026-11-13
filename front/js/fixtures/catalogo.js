/**
 * Bodegas del Atuel - Fixtures de catálogo de vinos (modo desarrollo).
 *
 * ESTE ARCHIVO SOLO SE USA CUANDO `USAR_FIXTURES` ES `true`.
 * Simula la forma EXACTA definida en docs/api-contrato.md (sección 4.1 Vinos
 * y sección 4.7 Catálogos auxiliares). Los datos son fijos y escritos a mano;
 * el front NO calcula totales, descuentos ni stock.
 */

/** Tipos de vino válidos (minúsculas, como el enum de la base). */
export const TIPOS_VINO = ["tinto", "blanco", "rosado", "espumante"];

/**
 * Lista de vinos con la forma EXACTA del ítem de GET /vinos del contrato:
 * { cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio,
 *   cuit_bodega, bodega_razon_social }.
 * Ninguna otra clave.
 */
export const listaVinosFixture = {
  items: [
    {
      cod_vino: 101,
      nombre: "Malbec Reserva",
      tipo: "tinto",
      anada: 2021,
      volumen_ml: 750,
      graduacion: "14.00",
      precio: "12500.00",
      cuit_bodega: "30123456789",
      bodega_razon_social: "Bodega del Atuel S.A.",
    },
    {
      cod_vino: 102,
      nombre: "Chardonnay Clásico",
      tipo: "blanco",
      anada: 2023,
      volumen_ml: 750,
      graduacion: "13.00",
      precio: "9800.00",
      cuit_bodega: "30987654321",
      bodega_razon_social: "Viñedos del Sur S.R.L.",
    },
    {
      cod_vino: 103,
      nombre: "Syrah Rosé",
      tipo: "rosado",
      anada: 2022,
      volumen_ml: 750,
      graduacion: "12.50",
      precio: "11000.00",
      cuit_bodega: "30123456789",
      bodega_razon_social: "Bodega del Atuel S.A.",
    },
    {
      cod_vino: 104,
      nombre: "Espumante Brut",
      tipo: "espumante",
      anada: 2020,
      volumen_ml: 750,
      graduacion: "12.00",
      precio: "15000.00",
      cuit_bodega: "30987654321",
      bodega_razon_social: "Viñedos del Sur S.R.L.",
    },
    {
      cod_vino: 105,
      nombre: "Cabernet Franc",
      tipo: "tinto",
      anada: 2021,
      volumen_ml: 750,
      graduacion: "14.50",
      precio: "13500.00",
      cuit_bodega: "30123456789",
      bodega_razon_social: "Bodega del Atuel S.A.",
    },
    {
      cod_vino: 106,
      nombre: "Torrontés Dulce",
      tipo: "blanco",
      anada: 2023,
      volumen_ml: 750,
      graduacion: "11.50",
      precio: "9200.00",
      cuit_bodega: "30987654321",
      bodega_razon_social: "Viñedos del Sur S.R.L.",
    },
  ],
  page: 1,
  page_size: 20,
  total: 6,
};

/**
 * Fichas de detalle indexadas por cod_vino, con la forma EXACTA del contrato
 * (sección 4.1 GET /vinos/{cod}): campos del ítem más
 * bodega { cuit, razon_social }, composicion [{ id_cepa, nombre, tipo, porcentaje }],
 * maridajes [{ id_maridaje, nombre, temperatura_servicio }] y
 * stock { deposito, salas, total }.
 */
export const detallesVinoFixture = {
  101: {
    cod_vino: 101,
    nombre: "Malbec Reserva",
    tipo: "tinto",
    anada: 2021,
    volumen_ml: 750,
    graduacion: "14.00",
    precio: "12500.00",
    bodega: {
      cuit: "30123456789",
      razon_social: "Bodega del Atuel S.A.",
    },
    composicion: [
      { id_cepa: 1, nombre: "Malbec", tipo: "tinta", porcentaje: "85.00" },
      { id_cepa: 2, nombre: "Cabernet Sauvignon", tipo: "tinta", porcentaje: "15.00" },
    ],
    maridajes: [
      { id_maridaje: 1, nombre: "Carnes rojas", temperatura_servicio: 17 },
      { id_maridaje: 2, nombre: "Quesos maduros", temperatura_servicio: 16 },
    ],
    stock: { deposito: 240, salas: 310, total: 550 },
  },
  102: {
    cod_vino: 102,
    nombre: "Chardonnay Clásico",
    tipo: "blanco",
    anada: 2023,
    volumen_ml: 750,
    graduacion: "13.00",
    precio: "9800.00",
    bodega: {
      cuit: "30987654321",
      razon_social: "Viñedos del Sur S.R.L.",
    },
    composicion: [
      { id_cepa: 3, nombre: "Chardonnay", tipo: "blanca", porcentaje: "100.00" },
    ],
    maridajes: [
      { id_maridaje: 3, nombre: "Pescados", temperatura_servicio: 10 },
    ],
    stock: { deposito: 120, salas: 80, total: 200 },
  },
  103: {
    cod_vino: 103,
    nombre: "Syrah Rosé",
    tipo: "rosado",
    anada: 2022,
    volumen_ml: 750,
    graduacion: "12.50",
    precio: "11000.00",
    bodega: {
      cuit: "30123456789",
      razon_social: "Bodega del Atuel S.A.",
    },
    composicion: [
      { id_cepa: 5, nombre: "Syrah", tipo: "tinta", porcentaje: "100.00" },
    ],
    maridajes: [
      { id_maridaje: 4, nombre: "Ensaladas", temperatura_servicio: 12 },
    ],
    stock: { deposito: 90, salas: 60, total: 150 },
  },
  104: {
    cod_vino: 104,
    nombre: "Espumante Brut",
    tipo: "espumante",
    anada: 2020,
    volumen_ml: 750,
    graduacion: "12.00",
    precio: "15000.00",
    bodega: {
      cuit: "30987654321",
      razon_social: "Viñedos del Sur S.R.L.",
    },
    composicion: [
      { id_cepa: 3, nombre: "Chardonnay", tipo: "blanca", porcentaje: "60.00" },
      { id_cepa: 1, nombre: "Malbec", tipo: "tinta", porcentaje: "40.00" },
    ],
    maridajes: [
      { id_maridaje: 5, nombre: "Mariscos", temperatura_servicio: 8 },
    ],
    stock: { deposito: 50, salas: 30, total: 80 },
  },
  105: {
    cod_vino: 105,
    nombre: "Cabernet Franc",
    tipo: "tinto",
    anada: 2021,
    volumen_ml: 750,
    graduacion: "14.50",
    precio: "13500.00",
    bodega: {
      cuit: "30123456789",
      razon_social: "Bodega del Atuel S.A.",
    },
    composicion: [
      { id_cepa: 2, nombre: "Cabernet Sauvignon", tipo: "tinta", porcentaje: "70.00" },
      { id_cepa: 5, nombre: "Syrah", tipo: "tinta", porcentaje: "30.00" },
    ],
    maridajes: [
      { id_maridaje: 1, nombre: "Carnes rojas", temperatura_servicio: 17 },
    ],
    stock: { deposito: 180, salas: 140, total: 320 },
  },
  106: {
    cod_vino: 106,
    nombre: "Torrontés Dulce",
    tipo: "blanco",
    anada: 2023,
    volumen_ml: 750,
    graduacion: "11.50",
    precio: "9200.00",
    bodega: {
      cuit: "30987654321",
      razon_social: "Viñedos del Sur S.R.L.",
    },
    composicion: [
      { id_cepa: 4, nombre: "Torrontés", tipo: "blanca", porcentaje: "100.00" },
    ],
    maridajes: [
      { id_maridaje: 6, nombre: "Postres", temperatura_servicio: 9 },
    ],
    stock: { deposito: 200, salas: 100, total: 300 },
  },
};

/**
 * Catálogo de cepas [{ id_cepa, nombre, tipo }] con tipo "tinta" | "blanca",
 * consistente con las composiciones de los vinos anteriores.
 */
export const cepasFixture = [
  { id_cepa: 1, nombre: "Malbec", tipo: "tinta" },
  { id_cepa: 2, nombre: "Cabernet Sauvignon", tipo: "tinta" },
  { id_cepa: 3, nombre: "Chardonnay", tipo: "blanca" },
  { id_cepa: 4, nombre: "Torrontés", tipo: "blanca" },
  { id_cepa: 5, nombre: "Syrah", tipo: "tinta" },
];

/**
 * Catálogo de bodegas [{ cuit, razon_social, domicilio }], consistente con
 * los cuit_bodega de los ítems anteriores.
 */
export const bodegasFixture = [
  {
    cuit: "30123456789",
    razon_social: "Bodega del Atuel S.A.",
    domicilio: "Ruta Nacional 143, San Rafael, Mendoza",
  },
  {
    cuit: "30987654321",
    razon_social: "Viñedos del Sur S.R.L.",
    domicilio: "Calle Falsa 123, San Carlos, Mendoza",
  },
];

/**
 * Lista de clientes con la forma EXACTA del ítem de GET /clientes del contrato
 * (sección 4.2): { id_cliente, apellido_razon_social, nombre, tipo_documento,
 * nro_documento, direccion, codigo_postal, fecha_alta, tipo_cliente,
 * descuento_pct }. `nombre` es null cuando el cliente es una razón social.
 */
export const clientesFixture = [
  {
    id_cliente: 1,
    apellido_razon_social: "Pérez",
    nombre: "Ana",
    tipo_documento: "DNI",
    nro_documento: "30111222",
    direccion: "Calle 123",
    codigo_postal: "M5600",
    fecha_alta: "2026-01-15",
    tipo_cliente: "socio",
    descuento_pct: "10.00",
  },
  {
    id_cliente: 2,
    apellido_razon_social: "García",
    nombre: "Luis",
    tipo_documento: "DNI",
    nro_documento: "27333444",
    direccion: "Av. Libertador 456",
    codigo_postal: "M5500",
    fecha_alta: "2026-02-10",
    tipo_cliente: "socio",
    descuento_pct: "10.00",
  },
  {
    id_cliente: 3,
    apellido_razon_social: "Rodríguez",
    nombre: "María",
    tipo_documento: "DNI",
    nro_documento: "32444555",
    direccion: "San Martín 789",
    codigo_postal: "M5600",
    fecha_alta: "2026-03-05",
    tipo_cliente: "distribuidor",
    descuento_pct: "20.00",
  },
  {
    id_cliente: 4,
    apellido_razon_social: "López",
    nombre: "Carlos",
    tipo_documento: "DNI",
    nro_documento: "30555666",
    direccion: "Belgrano 101",
    codigo_postal: "M5601",
    fecha_alta: "2026-03-20",
    tipo_cliente: "socio",
    descuento_pct: "10.00",
  },
  {
    id_cliente: 5,
    apellido_razon_social: "Bodega del Sur S.R.L.",
    nombre: null,
    tipo_documento: "CUIT",
    nro_documento: "30666777888",
    direccion: "Ruta 40 km 1100",
    codigo_postal: "M5605",
    fecha_alta: "2026-04-01",
    tipo_cliente: "distribuidor",
    descuento_pct: "20.00",
  },
  {
    id_cliente: 6,
    apellido_razon_social: "Fernández",
    nombre: "Sofía",
    tipo_documento: "DNI",
    nro_documento: "33777888",
    direccion: "Las Heras 222",
    codigo_postal: "M5600",
    fecha_alta: "2026-04-15",
    tipo_cliente: "socio",
    descuento_pct: "10.00",
  },
  {
    id_cliente: 7,
    apellido_razon_social: "Exportadora Mendoza S.A.",
    nombre: null,
    tipo_documento: "CUIT",
    nro_documento: "30777888999",
    direccion: "Parque Industrial Lote 5",
    codigo_postal: "M5507",
    fecha_alta: "2026-05-01",
    tipo_cliente: "exportador",
    descuento_pct: "30.00",
  },
  {
    id_cliente: 8,
    apellido_razon_social: "Gómez",
    nombre: "Martín",
    tipo_documento: "DNI",
    nro_documento: "30888999",
    direccion: "Colón 333",
    codigo_postal: "M5600",
    fecha_alta: "2026-05-20",
    tipo_cliente: "socio",
    descuento_pct: "10.00",
  },
];
