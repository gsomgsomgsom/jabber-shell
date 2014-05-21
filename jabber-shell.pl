#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use Net::XMPP;
use Net::Jabber;
use Encode;
use utf8;

# Список файлов конфигурации для перебора
my @configs = (
    './jabber-shell.conf',           # Конфиг в текущей директории
    $ENV{'HOME'}.'/.jabber-shell',   # Пользовательский файл конфигурации
    '/etc/jabber-shell.conf',        # Системный конфиг
);

# Хэш для хранения настроек
my %settings;

# Перебираем все файлы конфигурации
foreach my $config (@configs) {
    # Если файл существует и доступен для чтения
    if ( ( -e $config ) && ( -r $config) ) {
	# Читаем конфигурацию
	open(CONFIG, '<'.$config);
	local $/ = undef;
	my $config_data = <CONFIG>;
	close(CONFIG);
	%settings = eval($config_data);
	# Выходим из цикла
	last;
    }
}

# Если не удалось прочитать настройки - завершаем работу
if ( !%settings || !$settings{'server'} || !$settings{'username'} || !$settings{'password'} || !$settings{'admins'} ) {
    die("Can't read settings!");
}

# Массив, в котором будут JID админов
my @admins = split(' ', $settings{'admins'});

# Определяем основные перменные
my $client   = new Net::Jabber::Client() or die("Can't create Jabber::Client!");
my $presense = Net::Jabber::Presence->new() or die("Can't create Jabber::Presense!");

# Определяем обработчики событий
$client->SetCallBacks(
    'message' => \&on_message,
);

# Подключаемся к сети
# TODO: Обрабатывать ошибки подключения
$client->Connect(
    'hostname'        => $settings{'server'},
    'port'            => $settings{'port'} || 5222,
    'tls'		=> 1,
) or die("Can't connect to jabber-server!");

my @connect = $client->AuthSend(
    'username'        => $settings{'username'},
    'password'        => $settings{'password'},
    'resource'        => $settings{'resource'} || 'jabber-shell',
) or die("Can't auth on jabber-server!");

# Устанавливаем статус
$presense->SetType("available");
$presense->SetStatus("");
$client->Send($presense);

# Функция обработки команд
sub process_command {
    my $command = shift;
    my $message = '';
    
    # Если команда cd - пытаемся сменить директорию
    if	($command =~ s/^\s*cd\s+//) {
	if (chdir($command)) {
	    $message = 'Directory changed';
	}
	else {
	    $message = 'Directory NOT changed';
	}
    }
    # Если какая-то другая - выполняем её и возвращаем результат
    else {
	$message = `$command 2>&1`;
	$message = decode('utf-8', $message);
    }
    return $message;
}

# Функция обработки сообщений
sub on_message {
    my $mid = shift || return;
    my $msg = shift || return;
    
    # Команда, которую будем выполнять
    my $command = $msg->GetBody;
    # Получаем JID отправителя
    my $jid = new Net::XMPP::JID($msg->GetFrom)->GetJID("base");
    
    
    # Перебираем админов
    foreach my $admin (@admins) {
	# Если сообщение от одного из них
        if ($jid eq $admin) {
    	    # Обрабатываем сообщение и посылаем ответ
	    my $reply = Net::Jabber::Message->new();
	    $reply->SetMessage(
		'to'   => $msg->GetFrom,
		'body' => process_command($command),
	    );
	    $client->Send($reply);
	}
    }
}

# Цикл обработки сообщений
while (defined($client->Process)) {
}

# Этот код выполняется при завершении скрипта не зависимо от причины завершения
END {
    # Закрываем соединение если оно было
    $client->Disconnect() if $client->Connected();
}
