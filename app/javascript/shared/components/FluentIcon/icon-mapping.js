export const lucideToFluentMapping = {
  'i-lucide-volume-2': 'volume-up',
  'i-lucide-volume-1': 'volume-down',
  'i-lucide-volume-x': 'volume-mute',
  'i-lucide-volume-off': 'volume-mute',
  // Adicione mais mapeamentos conforme necessário
};

export const getFluentIconName = lucideIconName => {
  return lucideToFluentMapping[lucideIconName] || lucideIconName;
};
