import sampleC01 from './sample_C01.json';
import sampleC05 from './sample_C05.json';

export const CHILDREN = [
  { id: 'C01', label: 'Criança C01', idade: 12, readings: sampleC01 },
  { id: 'C05', label: 'Criança C05', idade: 10, readings: sampleC05 },
];

export const STRESS_LABELS = {
  nenhum: 'Sem sinais de estresse',
  leve: 'Estresse leve',
  moderado: 'Estresse moderado',
  alto: 'Estresse alto',
};

export const ACTIVITY_LABELS = {
  calmo: 'Calmo',
  atividade_leve: 'Atividade leve',
  brincadeira_ativa: 'Brincadeira ativa',
};
