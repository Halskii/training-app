const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const minTrainingDays = 2;
const maxTrainingDays = 5;

/// "Mar 1, 2027"
String formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

const goalKindLabels = {
  'long_term': 'Long-term',
  'phase': 'This training phase',
  'competition': 'Competition',
};
