import App from 'resource:///com/github/Aylur/ags/app.js';
import { subprocess, exec } from 'resource:///com/github/Aylur/ags/utils.js';
import Bar from './js/bar.js';

const scss = App.configDir + '/scss/style.scss';
const css = App.configDir + '/scss/style.css';

exec(`sassc ${scss} ${css}`);

subprocess([
    'inotifywait',
    '--recursive',
    '--event', 'create,modify',
    '-m', App.configDir + '/scss',
], () => {
    const scss = App.configDir + '/scss/style.scss';
    const css = App.configDir + '/scss/style.css';
    exec(`sassc ${scss} ${css}`);
    App.resetCss();
    App.applyCss(css);
});

export default {
    style: css,
    windows: [Bar(0)],
};
