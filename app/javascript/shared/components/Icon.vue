import { getFluentIconName } from './FluentIcon/icon-mapping'; export default {
methods: { getIconPath() { const fluentIconName = getFluentIconName(this.icon);
return this.icons[fluentIconName]?.path || ''; } } };
