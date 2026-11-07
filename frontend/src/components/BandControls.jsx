import { CONTROL_LIMITS, GYRO_ACTIONS, REGULARIDADE } from '../model/simulate';
import { formatClock } from './formatTime';

// "Controle da pulseira": os controles publicam os valores-alvo em
// puzzleband/<id>/controle e a pulseira, no modo controle (npm run controle),
// gera as leituras a partir deles. O resultado (leituras, nivel, episodios)
// volta da pulseira pelos topicos de sempre.
//
// `values`: { bpm, eda, hrv, movimento, regularidade, luz, ruido, idade }
// `notice`: { tone: 'ok' | 'warning', text } - situacao da pulseira

const L = CONTROL_LIMITS;

function Range({ label, display, field, value, onChange, step = 1, className }) {
  return (
    <label className="manual-controls__field">
      <span>{label}: <strong>{display}</strong></span>
      <input
        className={className}
        type="range"
        min={L[field].min}
        max={L[field].max}
        step={step}
        value={value}
        onChange={(e) => onChange(field, Number(e.target.value))}
      />
    </label>
  );
}

export default function BandControls({ values, onChange, onReset, notice, lastSentAt }) {
  const sentClock = formatClock(lastSentAt);
  const repetitivo = values.regularidade >= REGULARIDADE.repetitivo;

  return (
    <div className="manual-controls">
      <div className="sim-controls__row">
        <p className={`band-controls__notice band-controls__notice--${notice.tone}`} role="status">
          <span aria-hidden="true">{notice.tone === 'ok' ? '● ' : '▲ '}</span>
          {notice.text}
        </p>
        <button className="sim-controls__reset" onClick={onReset} type="button">
          ⟲ Voltar ao estado calmo
        </button>
      </div>
      <p className="band-controls__hint">
        Os valores vão para a pulseira no máximo 2 vezes por segundo; ela chega a cada novo valor numa transição de
        20 s, com o mesmo ruído dos sensores do simulador.
        {sentClock && ` Último envio às ${sentClock}.`}
      </p>

      <div className="manual-controls__group-label">Sensores fisiológicos</div>
      <div className="manual-controls__grid">
        <Range label="Batimento cardíaco" display={`${values.bpm} bpm`} field="bpm" value={values.bpm} onChange={onChange} className="manual-controls__bpm-range" />
        <Range label="Suor / EDA" display={`${values.eda.toFixed(1)} µS`} field="eda" value={values.eda} onChange={onChange} step={0.1} className="manual-controls__eda-range" />
        <Range label="HRV (variabilidade cardíaca)" display={`${values.hrv} ms`} field="hrv" value={values.hrv} onChange={onChange} className="manual-controls__hrv-range" />
        <Range label="Idade da criança" display={`${values.idade} anos`} field="idade" value={values.idade} onChange={onChange} />
      </div>

      <div className="manual-controls__group-label">Movimento (giroscópio + acelerômetro)</div>
      <div className="manual-controls__gyro">
        <span className="manual-controls__gyro-label">Intensidade — ação da criança</span>
        <div className="manual-controls__gyro-options">
          {GYRO_ACTIONS.map((action) => (
            <button
              key={action.id}
              type="button"
              className={`manual-controls__gyro-btn ${values.movimento === action.base ? 'is-active' : ''}`}
              aria-pressed={values.movimento === action.base}
              onClick={() => onChange('movimento', action.base)}
            >
              {action.label}
            </button>
          ))}
        </div>
      </div>
      <div className="manual-controls__toggle-row">
        <span className="manual-controls__gyro-label">Padrão do movimento</span>
        <button
          type="button"
          className={`manual-controls__toggle-btn ${!repetitivo ? 'is-active' : ''}`}
          aria-pressed={!repetitivo}
          onClick={() => onChange('regularidade', REGULARIDADE.livre)}
        >
          Livre / errático (ex.: correr)
        </button>
        <button
          type="button"
          className={`manual-controls__toggle-btn ${repetitivo ? 'is-active' : ''}`}
          aria-pressed={repetitivo}
          onClick={() => onChange('regularidade', REGULARIDADE.repetitivo)}
        >
          Repetitivo (estereotipia)
        </button>
      </div>

      <div className="manual-controls__group-label">Sensores ambientais</div>
      <div className="manual-controls__grid">
        <Range label="Luminosidade" display={`${values.luz} lux`} field="luz" value={values.luz} onChange={onChange} step={10} />
        <Range label="Ruído ambiente" display={`${values.ruido} dB`} field="ruido" value={values.ruido} onChange={onChange} />
      </div>
    </div>
  );
}
