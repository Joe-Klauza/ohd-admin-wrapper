require 'bcrypt'
require 'erb'
require 'fileutils'
require 'inifile'
require 'net/http'
require 'oj'
require 'socket'
require 'sysrandom'
require_relative 'logger'

# Used in server-monitor to avoid showing internal IPs for local players
# but OHD does not (yet?) provide player IP addresses like Insurgency: Sandstorm does
# LOCAL_IP_PREFIXES = ['10.', '0.', '127.','192.168.'] # https://en.wikipedia.org/wiki/Reserved_IP_addresses
# Thread.new { EXTERNAL_IP = Net::HTTP.get URI "https://api.ipify.org" rescue nil }

CONFIG_PATH = File.expand_path File.join File.dirname(__FILE__), '..', 'config'
CONFIG_FILE = File.join CONFIG_PATH, 'config.json'
USERS_CONFIG_FILE = File.join CONFIG_PATH, 'users.json'
MONITOR_CONFIGS_FILE = File.join CONFIG_PATH, 'monitor-configs.json'
SERVER_CONFIGS_FILE = File.join CONFIG_PATH, 'server-configs.json'
PLAYER_INFO_FILE = File.join CONFIG_PATH, 'players.json'

WRAPPER_ROOT = File.expand_path(File.join(File.dirname(__FILE__), '..', '..')).freeze
WRAPPER_CONFIG = File.join WRAPPER_ROOT, 'config'
WEBAPP_ROOT = File.join WRAPPER_ROOT, 'admin-interface'
WEBAPP_CONFIG = File.join(WRAPPER_CONFIG, 'config.toml')
WEBAPP_CONFIG_SAMPLE = File.join(WRAPPER_CONFIG, 'config.toml.sample')
GENERATED_SSL_CERT = File.join(WRAPPER_CONFIG, 'generated_ssl_cert.pem')
GENERATED_SSL_KEY = File.join(WRAPPER_CONFIG, 'generated_ssl_key.pem')
SERVER_ROOT = File.join WRAPPER_ROOT, 'ohd-server'
STEAMCMD_ROOT = File.join WRAPPER_ROOT, 'steamcmd'
STEAMCMD_EXE = File.join STEAMCMD_ROOT, 'installation', (WINDOWS ? "steamcmd.exe" : "steamcmd.sh")
STEAM_APPINFO_VDF = File.join STEAMCMD_ROOT, (WINDOWS ? "installation" : 'Steam'), 'appcache', 'appinfo.vdf'
USER_HOME = ENV['HOME'] unless USER_HOME
ENV['HOME'] = STEAMCMD_ROOT # Steam will pollute the user directory otherwise on Linux.

BINARY = File.join SERVER_ROOT, 'HarshDoorstop', 'Binaries', (WINDOWS ? 'Win64\HarshDoorstopServer-Win64-Shipping.exe' : 'Linux/HarshDoorstopServer-Linux-Shipping')
SERVER_LOG_DIR = File.join SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Logs'
RCON_LOG_FILE = File.join SERVER_LOG_DIR, 'HarshDoorstop.log'
CONFIG_FILES_DIR = File.join WRAPPER_ROOT, 'server-config'
FileUtils.mkdir_p CONFIG_FILES_DIR
CONFIG_FILES = {
  game_ini: {
    type: :ini,
    actual: File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'Game.ini'),
    local_erb: "<%=File.join(CONFIG_FILES_DIR, config_id, 'Game.ini')%>"
  },
  engine_ini: {
    type: :ini,
    actual: File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'Engine.ini'),
    local_erb: "<%=File.join(CONFIG_FILES_DIR, config_id, 'Engine.ini')%>"
  },
  game_user_settings_ini: {
    type: :ini,
    actual: File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'GameUserSettings.ini'),
    local_erb: "<%=File.join(CONFIG_FILES_DIR, config_id, 'GameUserSettings.ini')%>"
  },
  admins_cfg: {
    type: :txt,
    actual_erb: "<%=File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'Admins_' + config_id + '.cfg')%>",
    local_erb: "<%=File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'Admins_' + config_id + '.cfg')%>"
  },
  mapcycle_cfg: {
    type: :txt,
    actual_erb: "<%=File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'MapCycle_' + config_id + '.cfg')%>",
    local_erb: "<%=File.join(CONFIG_FILES_DIR, config_id, 'MapCycle.cfg')%>"
  },
  bans_cfg: {
    type: :txt,
    actual: File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'Bans.cfg'),
    local_erb: "<%=File.join(SERVER_ROOT, 'HarshDoorstop', 'Saved', 'Config', (WINDOWS ? 'WindowsServer' : 'LinuxServer'), 'Bans.cfg')%>"
  },
  motd_txt: {
    type: :txt,
    actual_erb: "<%=File.join(SERVER_ROOT, 'HarshDoorstop', 'Config', 'Server', 'Motd_' + config_id + '.txt')%>",
    local_erb: "<%=File.join(CONFIG_FILES_DIR, config_id, 'Motd.txt')%>"
  },
  notes_txt: {
    type: :txt,
    actual: nil,
    local_erb: "<%=File.join(CONFIG_FILES_DIR, config_id, 'Notes.txt')%>"
  },
}

MAPMAP = {
  'Argonne' => 'Argonne',
  'Montecassino' => ' Monte Cassino',
  'LamDong' => 'Lam Dong',
  'Khafji_P' => 'Khafji_P',
  'Risala' => 'Risala'
  # 'AAS-TestMap' => 'Test Map (AAS)'
  # 'SaintQuentin' => 'Saint Quentin',
  # 'OmahaBeach' => 'OmahaBeach',
  # 'Carentan' => 'Carentan',
  # 'Tan_Binh' => 'Tan_Binh'
}
MAPMAP_INVERTED = MAPMAP.invert
SIDES = [
  'Insurgents',
  'Security'
]
SCENARIO_MODES = [
]
GAME_MODES = [
  'Ambush',
  'Domination',
  'Firefight',
  'Frontline',
  'Occupy',
  'Skirmish',
  'CaptureTheBase',
  'TeamDeathmatch',
  'Filming',
  'Mission',
  'Checkpoint',
  'CheckpointHardcore',
  'CheckpointTutorial',
  'Operations',
  'Outpost',
  'Survival'
]
RULE_SETS = [
  'CheckpointFrenzy',
  'CompetitiveFirefight',
  'CompetitiveTheater',
  'MatchmakingCasual',
  'OfficialRules'
]
MUTATORS = {
  'AllYouCanEat' => { 'name' => 'All You Can Eat', 'description' => 'Start with 100 supply points.' },
  'AntiMaterielRiflesOnly' => { 'name' => 'Anti-Materiel Only', 'description' => 'Only anti-materiel rifles are available along with normal equipment and explosives.' },
  'BoltActionsOnly' => { 'name' => 'Bolt-Actions Only', 'description' =>'Only bolt-action rifles are available along with normal equipment and explosives.' },
  'Broke' => { 'name' => 'Broke', 'description' => 'Start with 0 supply points.' },
  'BudgetAntiquing' => {'name' => 'Budget Antiquing', 'description' => 'Only allows only old, cheap weapons along with normal equipment and explosives.' },
  'BulletSponge' => { 'name' => 'Bullet Sponge', 'description' => 'Health is increased.' },
  'Competitive' => { 'name' => 'Competitive', 'description' => 'Equipment is more expensive, rounds are shorter, and capturing objectives is faster.' },
  'CompetitiveLoadouts' => { 'name' => 'Competitive Loadouts', 'description' => 'Player classes are replaced with those from Competitive.' },
  'FastMovement' => { 'name' => 'Fast Movement', 'description' => 'Move faster.' },
  'Frenzy' => { 'name' => 'Frenzy', 'description' => 'Fight against AI enemies who only use melee attacks. Watch out for special enemies.' },
  'FullyLoaded' => {'name' => 'Fully Loaded', 'description' => 'All weapons, equipment, and explosives in the game are available in the Loadout Menu.' },
  'Guerrillas' => { 'name' => 'Guerrillas', 'description' => 'Start with 5 supply points.' },
  'Gunslingers' => {'name' => 'Gunslingers', 'description' => 'Players are equipped with the MR 73 revolver, normal equipment, and explosives.' },
  'Hardcore' => { 'name' => 'Hardcore', 'description' => 'Mutator featuring slower movement speeds and longer capture times.' },
  'HeadshotOnly' => { 'name' => 'Headshots Only', 'description' => 'Players only take damage when shot in the head.' },
  'HotPotato' => { 'name' => 'Hot Potato', 'description' => 'A live fragmentation grenade is dropped on death.' },
  'LockedAim' => { 'name' => 'Locked Aim', 'description' => 'Weapons always point to the center of the screen.' },
  'MakarovsOnly' => {'name' => 'Makarovs Only', 'description' => 'Makarov pistols only.' },
  'NoAim' => { 'name' => 'No Aim Down Sights', 'description' => 'Aiming down sights is disabled.' },
  'NoDrops' => {'name' => 'No Drops', 'description' => 'Weapons, explosives, and equipment are not dropped by dead players or enemy AI.' },
  'PistolsOnly' => { 'name' => 'Pistols Only', 'description' => 'Only pistols are available along with normal equipment and explosives.' },
  'Poor' => {'name' => 'Poor', 'description' => 'Players start with only 2 supply points' },
  'ShotgunsOnly' => { 'name' => 'Shotguns Only', 'description' => 'Only Shotguns are available along with normal equipment and explosives.' },
  'SlowCaptureTimes' => { 'name' => 'Slow Capture Times', 'description' => 'Objectives will take longer to capture.' },
  'SlowMovement' => { 'name' => 'Slow Movement', 'description' => 'Move slower.' },
  'SoldierOfFortune' => { 'name' => 'Soldier of Fortune', 'description' => 'Gain supply points as your score increases.' },
  'SpecialOperations' => { 'name' => 'Special Operations', 'description' => 'Start with 30 supply points.' },
  'Strapped' => { 'name' => 'Strapped', 'description' => 'Start with 1 supply point.' },
  'Ultralethal' => { 'name' => 'Ultralethal', 'description' => 'Everyone dies with one shot.' },
  'Vampirism' => { 'name' => 'Vampirism', 'description' => 'Receive health when dealing damage to enemies equal to the amount of damage dealt.' },
  'Warlords' => { 'name' => 'Warlords', 'description' => 'Start with 10 supply points.' }
}


class ConfigHandler
  attr_reader :monitor_configs
  attr_reader :server_configs
  attr_reader :users
  attr_reader :bans_thread
  attr_accessor :players

  def self.generate_password
    Sysrandom.base64(32 + Sysrandom.random_number(32)).gsub("\n", '')
  end

  CONFIG_VARIABLES = {
    'server-config-name' => {
      'default' => 'Default',
      'validation' => Proc.new { true }
    },
    'server_default_map' => {
      'default' => MAPMAP.keys.sample,
      'random' => false,
      'validation' => Proc.new { |map| !map.to_s.empty? },
      'type' => :map
    },
    'server_lighting_day' => {
      'default' => 'true',
      'validation' => Proc.new { |val| ['true', 'false'].include? val }
    },
    'server_default_side' => {
      'default' => SIDES.sample,
      'random' => false,
      'validation' => Proc.new { |side| SIDES.include?(side) || side == 'Random' }
    },
    'server_max_players' => {
      'default' => '8',
      'type' => :argument,
      'validation' => Proc.new do |num|
          num.to_s =~ /\A\d+\Z/
        rescue
          false
        end
    },
    'server_max_players_override' => {
      'default' => '10',
      'type' => :engine_ini,
      'validation' => Proc.new do |num|
          num.to_s =~ /\A\d+\Z/
        rescue
          false
        end,
      'getter' => Proc.new { |engine_ini| engine_ini['SystemSettings']['net.MaxPlayersOverride'] },
      'setter' => Proc.new { |engine_ini, players| engine_ini['SystemSettings']['net.MaxPlayersOverride'] = players }
    },
    'server_game_mode' => {
      'default' => 'None',
      'validation' => Proc.new { |mode| ['None'].concat(GAME_MODES).include? mode }
    },
    'server_scenario_mode' => {
      'default' => 'Checkpoint',
      'validation' => Proc.new { |mode| SCENARIO_MODES.include? mode }
    },
    'server_rule_set' => {
      'default' => 'None',
      'validation' => Proc.new { |rule_set| RULE_SETS.include?(rule_set) || rule_set = 'None' }
    },
    'server_mutators_custom' => {
      'default' => '',
      'validation' => Proc.new { true }
    },
    'server_mutators' => {
      'default' => [],
      'validation' => Proc.new { |mutators| mutators.all? { |mutator| MUTATORS.keys.include?(mutator) } }
    },
    'server_cheats' => {
      'default' => 'false',
      'validation' => Proc.new { |val| ['true', 'false'].include? val }
    },
    'server_name' => {
      'default' => 'OHD Admin Wrapper',
      'type' => :argument,
      'template' => '-hostname=<%= it %>',
      'validation' => Proc.new { true },
    },
    'server_password' => {
      'default' => '',
      'type' => :argument,
      'template' => '-password=<%= it %>',
      'validation' => Proc.new { true },
      'sensitive' => true
    },
    'server_game_port' => {
      'default' => '7777',
      'type' => :argument,
      'template' => '-Port=<%= it %>',
      'validation' => Proc.new { |port| ConfigHandler.valid_port? port }
    },
    'server_query_port' => {
      'default' => '27131',
      'type' => :argument,
      'template' => '-QueryPort=<%= it %>',
      'validation' => Proc.new { |port| ConfigHandler.valid_port? port }
    },
    'server_rcon_enabled' => {
      'default' => 'true',
      'type' => :game_ini,
      'getter' => Proc.new { |game_ini| game_ini['/Script/RCON.RCONServerSystem']['bEnabled'] },
      'setter' => Proc.new { |game_ini, bool| game_ini['/Script/RCON.RCONServerSystem']['bEnabled'] = bool.to_s.casecmp('true').zero? ? 'True' : 'False' },
      'validation' => Proc.new { true }
    },
    'server_rcon_port' => {
      'default' => '27015',
      'type' => :game_ini,
      'getter' => Proc.new { |game_ini| game_ini['/Script/RCON.RCONServerSystem']['ListenPort'] },
      'setter' => Proc.new { |game_ini, port| game_ini['/Script/RCON.RCONServerSystem']['ListenPort'] = port },
      'validation' => Proc.new { |port| ConfigHandler.valid_port? port }
    },
    'server_rcon_password' => {
      'default' => ConfigHandler.generate_password,
      'type' => :game_ini,
      'getter' => Proc.new { |game_ini| game_ini['/Script/RCON.RCONServerSystem']['Password'] },
      'setter' => Proc.new { |game_ini, password| game_ini['/Script/RCON.RCONServerSystem']['Password'] = password },
      'validation' => Proc.new { true },
      'sensitive' => true
    },
    'server_gst' => {
      'default' => '',
      'type' => :argument,
      'validation' => Proc.new { |token| token =~ /\A[ABCDEF0-9]+\Z/ || token.empty? },
      'sensitive' => true
    },
    'server_gslt' => {
      'default' => '',
      'type' => :argument,
      'validation' => Proc.new { |token| token =~ /\A[ABCDEF0-9]+\Z/ || token.empty? },
      'sensitive' => true
    },
    'server_custom_server_args' => {
      'default' => '',
      'validation' => Proc.new { true }
    },
    'server_custom_travel_args' => {
      'default' => '',
      'validation' => Proc.new { true }
    },
    'hang_recovery' => {
      'default' => 'true',
      'validation' => Proc.new { |val| ['true', 'false'].include? val }
    },
    'query_recovery' => {
      'default' => 'true',
      'validation' => Proc.new { |val| ['true', 'false'].include? val }
    },
    'join_message' => {
      'default' => 'Welcome, ${player_name}!',
      'validation' => Proc.new { true }
    },
    'leave_message' => {
      'default' => 'See you later, ${player_name}!',
      'validation' => Proc.new { true }
    },
    'admin_join_message' => {
      'default' => 'Welcome, ${player_name}! (admin)',
      'validation' => Proc.new { true }
    },
    'admin_leave_message' => {
      'default' => 'See you later, ${player_name}! (admin)',
      'validation' => Proc.new { true }
    }
  }

  def initialize
    @users = load_user_config
    @monitor_configs = load_monitor_configs
    @server_configs = load_server_configs
    @players = load_player_config
  end

  def self.valid_port?(port)
    port = port.to_i
    port >= 1 && port <= 65535
  rescue
    false
  end

  def self.sanitize_directory(directory_name)
    directory_name.gsub(/[^ 0-9A-Za-z.\-'"]/, '')
  end

  def get_uuid(uuid=Sysrandom.uuid)
    return uuid if @server_configs.nil? || @server_configs.empty?
    while @server_configs.keys.include?(uuid)
      uuid = Sysrandom.uuid
    end
    uuid
  end

  def get_default_config
    defaults = {'id' => get_uuid}
    CONFIG_VARIABLES.each { |k, v| defaults[k] = v['default'] }
    defaults
  end

  def get_default_user_config
    default_admin_user = User.new('admin', :host, password: BCrypt::Password.create('password').to_s, initial_password: 'password')
    {
      default_admin_user.id => default_admin_user
    }
  end

  def load_user_config
    @users = Oj.load(File.read(USERS_CONFIG_FILE))
    @users = get_default_user_config if @users.to_s.strip.empty?
    @users
  rescue Errno::ENOENT
    get_default_user_config
  rescue => e
    log "Failed to load user config from #{USERS_CONFIG_FILE}. Using default user config.", e
    raise
  end

  def load_monitor_configs
    @monitor_configs = Oj.load(File.read(MONITOR_CONFIGS_FILE))
    @monitor_configs = {} if @monitor_configs.to_s.empty?
    @monitor_configs.each { |_, config| config['id'] ||= get_uuid }
    @monitor_configs
  rescue Errno::ENOENT
    {}
  rescue => e
    log "Failed to load monitor configs from #{MONITOR_CONFIGS_FILE}. Using empty config.", e
    raise
  end

  def add_server_config(config)
    @server_configs[config['id']] = config
  end

  def get_server_configs_skeleton
    skeleton = {}
    default_config = get_default_config
    skeleton[default_config['id']] = default_config
  end

  def load_server_configs
    @server_configs = Oj.load(File.read(SERVER_CONFIGS_FILE))
    if @server_configs.nil? || @server_configs.empty?
      @server_configs = {}
      add_server_config(get_default_config)
    end
    # Ensure all keys are IDs, else convert automatically
    @server_configs.select { |k, _| !k.is_uuid? }.keys.each do |key|
      log "Replacing config key '#{key}' with an ID"
      config = @server_configs[key]
      id = config['id'] || get_uuid
      config['id'] = id
      @server_configs[id] = config
      @server_configs.delete(key)
    end
    # Ensure all configs have latest config params
    @server_configs.each do |id, config|
      @server_configs[id] = get_default_config.merge(config)
    end
    init_server_config_files
    @server_configs
  rescue Errno::ENOENT
    {'Default' => get_default_config}
  rescue => e
    log "Failed to load server configs from #{SERVER_CONFIGS_FILE}. Using empty config.", e
    raise
  end

  def load_player_config
    Oj.load(File.read(PLAYER_INFO_FILE))
  rescue Errno::ENOENT
    {}
  rescue => e
    log "Failed to load user config from #{USERS_CONFIG_FILE}. Using default user config.", e
    raise
  end

  def write_user_config
    log "Writing user config"
    File.write(USERS_CONFIG_FILE, Oj.dump(@users, indent: 2))
  end

  def write_monitor_configs
    log "Writing monitor configs"
    File.write(MONITOR_CONFIGS_FILE, Oj.dump(@monitor_configs, indent: 2))
  end

  def create_server_config(incoming_config)
    config_id = incoming_config['id']
    config_name = incoming_config['server-config-name']
    overwrote = false
    outgoing_config = if config_id && @server_configs[config_id] && @server_configs[config_id]['server-config-name'] == config_name
      overwrote = true
      log "Writing server config:  #{config_id} #{config_name}", level: :info
      @server_configs[config_id] = get_default_config.merge(incoming_config)
    else
      new_config = get_default_config
      config_id = new_config['id']
      log "Creating server config: #{config_id} #{config_name}", level: :info
      @server_configs[config_id] = get_default_config.merge(incoming_config)
          .merge({
            'id' => config_id, # Ignore provided config ID
          })
    end
    write_server_configs
    init_server_config_files(config_id)
    outgoing_config
  end

  def delete_server_config(config_id)
    config = @server_configs[config_id]
    config_name = config['server-config-name']
    log "Deleting server config: #{config_id} #{config_name}", level: :info
    @server_configs.delete config_id
    CONFIG_FILES.reject { |f, _| [:bans_cfg, :admins_cfg].include?(f) }.values.each do |it|
      local = ERB.new(it[:local_erb]).result(binding)
      FileUtils.rm local
    rescue Errno::ENOENT
    rescue => e
      log "Error while trying to delete file (#{local})", e
    end
    begin
      dir = File.join(CONFIG_FILES_DIR, config_id)
      FileUtils.rmdir dir
    rescue Errno::ENOENT
    rescue => e
      log "Error while trying to delete directory (#{dir})", e
    end
    add_server_config(get_default_config) if @server_configs.empty?
    write_server_configs
    nil
  end

  def write_server_configs
    log "Writing server configs"
    File.write(SERVER_CONFIGS_FILE, Oj.dump(@server_configs, indent: 2))
    nil
  end

  def write_player_info
    log "Writing player info"
    File.write(PLAYER_INFO_FILE, Oj.dump(@players, indent: 2))
    nil
  end

  def write_config
    write_user_config
    write_monitor_configs
    write_server_configs
    write_player_info
    true
  rescue => e
    log 'Failed to write config', e
    false
  end

  def init_server_config_files(config_id=nil)
    config_ids = @server_configs.values.map { |c| c['id'] }
    config_ids = config_id.nil? ? config_ids : [config_id]
    config_ids.reject{ |id| !config_ids.include?(id) }.each do |config_id|
      CONFIG_FILES.values.each do |it|
        [ERB.new(it[:local_erb]).result(binding), it[:actual], it[:actual_erb] && ERB.new(it[:actual_erb]).result(binding)].each do |path|
          next if path.nil?
          FileUtils.mkdir_p File.dirname path
          FileUtils.touch path
        end
      end
    end
    nil
  end

  def apply_server_config_files(config)
    config_id = config['id'] # Needed for bindings
    # Apply values in case any in memory aren't in the file
    apply_game_ini_local config
    apply_engine_ini_local config

    # Remove :delete files so that the server doesn't use any the user may have manually set outside of OHDAW
    CONFIG_FILES.reject {|_,i| i[:delete].nil? }.values.each do |it|
      local = ERB.new(it[:delete]).result(binding)
      log "Deleting #{local}"
      FileUtils.rm local
    rescue Errno::ENOENT
    rescue => e
      log "Error while trying to delete file (#{local})", e
    end

    CONFIG_FILES.reject {|_,i| i[:actual].nil? && i[:actual_erb].nil? }.values.each do |it|
      local = ERB.new(it[:local_erb]).result(binding) # relies on config_id
      actual = it[:actual_erb] ? ERB.new(it[:actual_erb]).result(binding) : it[:actual] # relies on config_id for actual_erb if present
      if local == actual
        log "Skipping #{local} -> #{actual} (same file)"
        return
      end
      log "Applying #{local} -> #{actual}"
      FileUtils.cp local, actual
    rescue => e
      log "Error while trying to copy file (#{local} -> #{actual})", e
    end
    nil
  end

  def get_server_config_file_content(config_file, config_id)
    local = ERB.new(CONFIG_FILES[config_file][:local_erb]).result(binding)
    File.read(local)
  end

  def set(config_id, variable, value)
    return [false, "Variable not in config: #{variable}"] unless CONFIG_VARIABLES.keys.include? variable
    return [false, "Variable has no validation: #{variable}"] unless CONFIG_VARIABLES[variable]['validation'].respond_to?('call')
    config = (@server_configs[config_id] = get_default_config.merge(@server_configs[config_id] || {}))
    old_value = config[variable]
    return [false, "Variable #{variable} is already set to #{CONFIG_VARIABLES[variable]['sensitive'] ? '[REDACTED]' : value}."] if value.to_s == old_value.to_s
    status = false
    msg = "Failed to set #{variable.inspect} to #{CONFIG_VARIABLES[variable]['sensitive'] ? '[REDACTED]' : value.inspect}"
    old_value = old_value || CONFIG_VARIABLES[variable]['default'] || 'Unknown'

    if CONFIG_VARIABLES[variable]['validation'].call(value)
      log "Value passed validation: #{CONFIG_VARIABLES[variable]['sensitive'] ? '[REDACTED]' : value.inspect}"
      config[variable] = value
      write_server_configs
      apply_game_ini_local(@server_configs[config_id]) if CONFIG_VARIABLES[variable]['type'] == :game_ini
      apply_engine_ini_local(@server_configs[config_id]) if CONFIG_VARIABLES[variable]['type'] == :engine_ini
      status = true
    else
      msg = "Value failed validation for variable #{variable.inspect}: #{CONFIG_VARIABLES[variable]['sensitive'] ? '[REDACTED]' : value.inspect}"
      log msg, level: :warn
    end

    return [status, msg, CONFIG_VARIABLES[variable]['sensitive'] ? '[REDACTED]' : config[variable], CONFIG_VARIABLES[variable]['sensitive'] ? '[REDACTED]' : old_value]
  end

  def get(config_id, variable)
    @server_configs[config_id][variable]
  end

  def get_log_file(config_id)
    log_file = File.join(SERVER_LOG_DIR, "#{config_id}.log")
    FileUtils.mkdir_p File.dirname log_file
    begin
      FileUtils.touch log_file
    rescue Errno::EACCES
      log "Unable to access log file: #{log_file}"
    end
    log_file
  end

  def get_scenario(map, mode, side)
    filtered_map = MAPMAP[map] || map
    "Scenario_#{filtered_map}_#{mode}#{'_' << side if ['Checkpoint', 'Push'].include?(mode)}"
  end

  def get_additional_travel_args(config)
    # Split using regex for unquoted strings
    config['server_custom_travel_args'].dup.to_s.split(/[ ]+(?=[^"]*(?:"[^"]*"[^"]*)*$)/)
  end

  def get_query_string(config, map: nil, side: nil, game_mode: nil, max_players: nil, password: nil)
    map = config['server_default_map'] == 'Random' ? MAPMAP.keys.sample : config['server_default_map'].dup if map.nil?
    game_mode = config['server_game_mode'] == 'Random' ? GAME_MODES.sample : config['server_game_mode'].dup if game_mode.nil?
    max_players ||= config['server_max_players'].dup
    password ||= config['server_password'].dup
    query = map.dup
    query << "?MaxPlayers=#{max_players}"
    query << "?Game=#{game_mode}" unless game_mode == 'None'
    query << "?Password=#{password}" unless password.empty?
    get_additional_travel_args(config).each do |arg|
      query << arg
    end
    query
  end

  def get_additional_server_args(config)
    # Split using regex for unquoted strings
    config['server_custom_server_args'].dup.split(/[ ]+(?=[^"]*(?:"[^"]*"[^"]*)*$)/)
  end

  def get_server_arguments(config)
    arguments = []
    map = config['server_default_map'].dup
    starting_map = map == 'Random' ? MAPMAP.keys.sample : map
    starting_map = MAPMAP.keys.include?(starting_map) ? starting_map : (MAPMAP.keys.include?(MAPMAP.key(starting_map)) ? MAPMAP.key(starting_map) : MAPMAP.keys.first )
    arguments.push(
      get_query_string(config, map: starting_map),
      "-ServerName=#{config['server_name']}",
      "-MaxPlayers=#{config['server_max_players']}",
      "-Port=#{config['server_game_port']}",
      "-QueryPort=#{config['server_query_port']}",
      "-log=#{config['id']}.log",
      "-LogCmds=LogGameplayEvents Log",
      "-LOCALLOGTIMES",
      "-AdminList=Admins_#{config['id']}.cfg",
      "-MapCycle=MapCycle_#{config['id']}.cfg"
    )
    custom_args = get_additional_server_args(config)
    arguments.concat(custom_args)
    arguments
  end

  def apply_game_ini_local(config)
    # config_id needed in binding
    config_id = config['id']
    apply_ini(config, ERB.new(CONFIG_FILES[:game_ini][:local_erb]).result(binding))
  end

  def apply_engine_ini_local(config)
    # config_id needed in binding
    config_id = config['id']
    apply_ini(config, ERB.new(CONFIG_FILES[:engine_ini][:local_erb]).result(binding))
  end

  def apply_ini(config, path)
    type = File.basename(path).downcase.sub('.', '_').to_sym
    log "Applying #{type} values to #{path}"
    ini = IniFile.load(path)
    changed = false
    CONFIG_VARIABLES.select { |_, metadata| metadata['type'] == type }.each do |option, metadata|
      next if (metadata['getter'].call(ini).to_s) == config[option].to_s
      changed = true
      log "Applying #{option}"
      metadata['setter'].call(ini, config[option])
    end
    if changed
      log "Saving #{type}"
      ini.save
    else
      log "No #{type} changes"
    end
  rescue => e
    log "Error while applying #{type} settings", e
    raise
  end
end
