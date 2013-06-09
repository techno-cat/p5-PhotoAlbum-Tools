requires 'perl', '5.008001';

on 'test' => sub {
    requires 'Test::More',      '0.98';
    requires 'Imager',          '0.94';
    requires 'Test::Exception', '0.31';
    requires 'File::Path',      '2.08_01';
};

