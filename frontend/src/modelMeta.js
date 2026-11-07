// Rodape do painel. O painel NAO roda o modelo (quem roda e a pulseira), entao
// importa so o campo "meta" do forest.json: com o import nomeado, o Vite deixa
// as arvores (~370 KB) fora do bundle do site.
import { meta } from './model/forest.json';
import { describeModel, modelInfoFrom } from './model/modelInfo';

export const MODEL_DESCRIPTION = `${describeModel(modelInfoFrom(meta))} · roda na pulseira (processamento na borda), não no navegador`;
