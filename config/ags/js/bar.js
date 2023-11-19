import { Variable } from 'resource:///com/github/Aylur/ags/variable.js';
import { Widget } from 'resource:///com/github/Aylur/ags/widget.js';
import System from './modules/system.js';

const time = new Variable('', {
    poll: [1000, 'date'],
});

const Bar = (/** @type {number} */ monitor) => Widget.Window({
    monitor,
    name: `bar${monitor}`,
    anchor: ['top', 'left', 'right'],
    exclusivity: 'exclusive',
    child: Widget.CenterBox({
        start_widget: System,
        end_widget: Widget.Label({
            hpack: 'center',
            binds: [['label', time]],
        }),
    }),
});

export default Bar;
