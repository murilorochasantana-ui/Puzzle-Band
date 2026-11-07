import { useEffect, useState } from 'react';
import { aplicarTema, lerTema, salvarTema } from '../theme';

// Icone + texto em cada opcao; o icone e decorativo (aria-hidden).
const OPCOES = [
  { id: 'sistema', icone: '◐', rotulo: 'Sistema', dica: 'Seguir o tema do sistema operacional' },
  { id: 'claro', icone: '☀', rotulo: 'Claro', dica: 'Tema claro' },
  { id: 'escuro', icone: '☾', rotulo: 'Escuro', dica: 'Tema escuro' },
];

/**
 * Tema do painel: Sistema (padrao), Claro ou Escuro. Botoes com
 * aria-pressed. Salvo no localStorage e aplicado no <html> (src/theme.js).
 */
export default function ThemeToggle() {
  const [tema, setTema] = useState(lerTema);

  useEffect(() => {
    aplicarTema(tema);
    salvarTema(tema);
  }, [tema]);

  return (
    <div className="source-select theme-select" role="group" aria-label="Tema do painel">
      <span className="source-select__label">Tema</span>
      <div className="source-select__options">
        {OPCOES.map((opcao) => (
          <button
            key={opcao.id}
            type="button"
            className={`manual-controls__toggle-btn ${tema === opcao.id ? 'is-active' : ''}`}
            aria-pressed={tema === opcao.id}
            title={opcao.dica}
            onClick={() => setTema(opcao.id)}
          >
            <span className="theme-select__icon" aria-hidden="true">{opcao.icone}</span>
            {opcao.rotulo}
          </button>
        ))}
      </div>
    </div>
  );
}
