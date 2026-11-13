import { usandoFixtures } from "./vinos-fuente.js";
import { buscarClientesSimulado } from "../fixtures/simulador.js";
import { listarClientes } from "../api/index.js";

export async function buscarClientes(filtros = {}) {
  if (usandoFixtures()) {
    return buscarClientesSimulado(filtros);
  }
  return listarClientes(filtros);
}