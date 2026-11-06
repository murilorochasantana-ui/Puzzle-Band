import { useEffect, useRef, useState } from 'react';
import { episodesToCsv, summarizeByChild, OBSERVATION_MAX_LENGTH } from '../model/episodes';
import { HISTORY_TOPIC_LIMIT } from '../hooks/buildMessages';
import { formatClock } from './formatTime';

const LEVEL_INFO = {
  atencao: { color: 'var(--status-warning)', ink: 'var(--status-warning-ink)', icon: '▲', label: 'Atenção' },
  alto_risco: { color: 'var(--status-critical)', ink: 'var(--status-critical-ink)', icon: '⛔', label: 'Possível crise' },
};

const SOURCE_LABEL = { manual: 'Simulador manual', mqtt: 'Pulseira (MQTT)' };

const EVALUATION_INFO = {
  pendente: { icon: '○', label: 'pendente' },
  confirmado: { icon: '✓', label: 'confirmado pelo cuidador' },
  descartado: { icon: '✕', label: 'descartado pelo cuidador' },
};

const PAGE_SIZE = 10;

const childName = (id) => (id === 'simulada' ? 'Criança simulada' : `Criança ${id}`);
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

function formatDuration(seconds) {
  if (!Number.isFinite(seconds)) return '—';
  const total = Math.round(seconds);
  const min = Math.floor(total / 60);
  const sec = total % 60;
  return min ? `${min} min ${sec} s` : `${sec} s`;
}

function formatStart(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

function downloadCsv(episodes) {
  const blob = new Blob([episodesToCsv(episodes)], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const stamp = new Date().toISOString().slice(0, 19).replace(/[-:]/g, '').replace('T', '_');
  const link = document.createElement('a');
  link.href = url;
  link.download = `puzzleband_historico_${stamp}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

function PatternSummary({ episodes }) {
  const groups = summarizeByChild(episodes);
  return (
    <div className="episode-summary">
      {groups.map((g) => {
        const line = (label, data) => (
          <li>
            {label}: <strong>{data.total} de {g.total}</strong> {g.total === 1 ? 'episódio' : 'episódios'}
            <span className="episode-summary__confirmed">
              {' · '}{plural(data.confirmados, 'confirmado', 'confirmados')} pelo cuidador
            </span>
          </li>
        );
        return (
          <section key={g.crianca} className="episode-summary__child" aria-label={`Padrões de ${childName(g.crianca)}`}>
            <h3>{childName(g.crianca)}</h3>
            <p className="episode-summary__totals">
              {plural(g.total, 'episódio', 'episódios')}
              {' · '}duração média {formatDuration(g.duracao_media_s)}
              {g.em_andamento > 0 && ' · 1 em andamento'}
            </p>
            <ul>
              {line('Ruído como provável gatilho', g.gatilhos.ruido)}
              {line('Luminosidade como provável gatilho', g.gatilhos.luminosidade)}
              {line('Sem gatilho ambiental aparente', g.gatilhos.nenhum_ambiental)}
            </ul>
            <p className="episode-summary__evaluation">
              Avaliação do cuidador: <span aria-hidden="true">✓</span> {plural(g.avaliacao.confirmado, 'confirmado', 'confirmados')}
              {' · '}<span aria-hidden="true">✕</span> {plural(g.avaliacao.descartado, 'descartado', 'descartados')}
              {' · '}<span aria-hidden="true">○</span> {plural(g.avaliacao.pendente, 'pendente', 'pendentes')}
            </p>
          </section>
        );
      })}
    </div>
  );
}

function EpisodeItem({ episode, onEvaluate, onObservation }) {
  const level = LEVEL_INFO[episode.nivel_maximo] ?? LEVEL_INFO.atencao;
  const evaluation = EVALUATION_INFO[episode.avaliacao_cuidador] ?? EVALUATION_INFO.pendente;
  const running = !episode.encerramento;
  const when = formatStart(episode.inicio);
  const obsId = `obs-${episode.id}`;
  const toggle = (value) => onEvaluate(episode.id, episode.avaliacao_cuidador === value ? 'pendente' : value);
  const trigger = episode.gatilho;
  // Avaliacao feita no app do cuidador (puzzleband/<id>/avaliacao)
  const byApp = episode.avaliacao_origem === 'app' && episode.avaliacao_cuidador !== 'pendente';
  const byAppClock = byApp ? formatClock(episode.avaliacao_em) : null;
  const seenClock = formatClock(episode.visto_pelo_cuidador_em);

  return (
    <li className="episode">
      <div className="episode__head">
        <span className="episode__time">{when}</span>
        <span className="episode__level" style={{ '--level-color': level.color, '--level-ink': level.ink }}>
          <span className="episode__level-icon" aria-hidden="true">{level.icon}</span>
          {level.label}
        </span>
        {running && <span className="episode__tag episode__tag--running">em andamento</span>}
        {episode.encerramento === 'interrompido' && <span className="episode__tag">interrompido</span>}
      </div>

      <dl className="episode__facts">
        <div>
          <dt>Duração</dt>
          <dd>{running ? `em andamento (${formatDuration(episode.duracao_s)})` : formatDuration(episode.duracao_s)}</dd>
        </div>
        <div>
          <dt>Prob. máxima</dt>
          <dd>{Math.round(episode.probabilidade_maxima * 100)}%</dd>
        </div>
        <div>
          <dt>Fonte</dt>
          <dd>{SOURCE_LABEL[episode.fonte] ?? episode.fonte}</dd>
        </div>
        <div>
          <dt>Criança</dt>
          <dd>{childName(episode.crianca)}</dd>
        </div>
      </dl>

      {/* o texto ja comeca com a classificacao ("Provavel gatilho: ..." / "Sem gatilho ...") */}
      <p className="episode__trigger">{trigger?.texto ?? 'Gatilho não calculado.'}</p>

      {seenClock && (
        <p className="episode__seen">
          <span aria-hidden="true">✓ </span>Alerta visto pelo cuidador às {seenClock}
        </p>
      )}

      <div className="episode__actions">
        <button
          type="button"
          className="episode-btn"
          aria-pressed={episode.avaliacao_cuidador === 'confirmado'}
          aria-label={`Confirmar gatilho do episódio de ${when}`}
          onClick={() => toggle('confirmado')}
        >
          <span aria-hidden="true">✓ </span>Confirmar gatilho
        </button>
        <button
          type="button"
          className="episode-btn"
          aria-pressed={episode.avaliacao_cuidador === 'descartado'}
          aria-label={`Descartar indicação do episódio de ${when}`}
          onClick={() => toggle('descartado')}
        >
          <span aria-hidden="true">✕ </span>Descartar
        </button>
        <span className="episode__evaluation">
          Avaliação: <span aria-hidden="true">{evaluation.icon}</span> {evaluation.label}
          {byApp && (
            <span className="episode__tag episode__tag--app">
              avaliado pelo app{byAppClock && ` às ${byAppClock}`}
            </span>
          )}
        </span>
      </div>

      <div className="episode__observation">
        <label htmlFor={obsId}>Observação (opcional)</label>
        <input
          id={obsId}
          type="text"
          maxLength={OBSERVATION_MAX_LENGTH}
          value={episode.observacao}
          placeholder="Ex.: sirene da escola tocou antes"
          onChange={(e) => onObservation(episode.id, e.target.value)}
        />
      </div>
    </li>
  );
}

export default function EpisodeHistory({ episodes, storageOk, onEvaluate, onObservation, onClear }) {
  const [confirming, setConfirming] = useState(false);
  const [visible, setVisible] = useState(PAGE_SIZE);
  const headingRef = useRef(null);
  const clearRef = useRef(null);
  const cancelRef = useRef(null);
  const empty = episodes.length === 0;

  useEffect(() => {
    if (confirming) cancelRef.current?.focus();
  }, [confirming]);

  const cancelClear = () => {
    setConfirming(false);
    clearRef.current?.focus();
  };
  const confirmClear = () => {
    onClear();
    setConfirming(false);
    setVisible(PAGE_SIZE);
    headingRef.current?.focus();
  };

  return (
    <section className="episode-history" aria-labelledby="episode-history-title">
      <div className="episode-history__header">
        <div>
          <h2 id="episode-history-title" ref={headingRef} tabIndex={-1}>Histórico de episódios</h2>
          <p className="episode-history__hint">
            Um episódio começa quando o nível sai de “Sem sinais de crise” e termina após 30 s de volta ao normal.
            Salvo neste navegador; os {HISTORY_TOPIC_LIMIT} mais recentes também vão para o app do cuidador (MQTT).
          </p>
        </div>
        <div className="episode-history__tools">
          <button type="button" className="episode-btn" disabled={empty} onClick={() => downloadCsv(episodes)}>
            Exportar CSV
          </button>
          <button
            type="button"
            ref={clearRef}
            className="episode-btn episode-btn--danger"
            disabled={empty}
            aria-expanded={confirming}
            aria-controls="episode-history-confirm"
            onClick={() => setConfirming(true)}
          >
            Limpar histórico
          </button>
        </div>
      </div>

      {confirming && (
        <div
          id="episode-history-confirm"
          className="episode-history__confirm"
          role="group"
          aria-labelledby="episode-history-confirm-text"
          onKeyDown={(e) => {
            if (e.key === 'Escape') cancelClear();
          }}
        >
          <p id="episode-history-confirm-text">
            <span aria-hidden="true">⚠ </span>
            Apagar {plural(episodes.length, 'episódio salvo', 'episódios salvos')} neste navegador? Esta ação não
            pode ser desfeita. Se quiser guardar os dados, exporte o CSV antes.
          </p>
          <div className="episode-history__confirm-actions">
            <button type="button" className="episode-btn episode-btn--danger-solid" onClick={confirmClear}>
              Sim, apagar histórico
            </button>
            <button type="button" ref={cancelRef} className="episode-btn" onClick={cancelClear}>
              Cancelar
            </button>
          </div>
        </div>
      )}

      {!storageOk && (
        <p className="episode-history__warning" role="status">
          <span aria-hidden="true">⚠ </span>
          Não foi possível salvar no navegador: o histórico vale só enquanto esta página estiver aberta.
        </p>
      )}

      {empty ? (
        <p className="episode-history__empty">Nenhum episódio registrado ainda.</p>
      ) : (
        <>
          <PatternSummary episodes={episodes} />
          <ol className="episode-list" aria-label="Episódios, do mais recente para o mais antigo">
            {episodes.slice(0, visible).map((ep) => (
              <EpisodeItem key={ep.id} episode={ep} onEvaluate={onEvaluate} onObservation={onObservation} />
            ))}
          </ol>
          {episodes.length > visible && (
            <button type="button" className="episode-btn episode-history__more" onClick={() => setVisible((v) => v + PAGE_SIZE)}>
              Mostrar mais ({episodes.length - visible} restantes)
            </button>
          )}
        </>
      )}
    </section>
  );
}
