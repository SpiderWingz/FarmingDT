CREATE TABLE IF NOT EXISTS `public_farming_plots` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_identifier` VARCHAR(100) NOT NULL,
  `layout_key` VARCHAR(32) NOT NULL,
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` FLOAT NOT NULL DEFAULT 0,
  `created_at` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_public_farming_owner` (`owner_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `public_farming_slots` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plot_id` INT UNSIGNED NOT NULL,
  `slot_index` SMALLINT UNSIGNED NOT NULL,
  `crop_key` VARCHAR(64) NULL,
  `planted_at` INT UNSIGNED NULL,
  `water` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `fertility` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `disease` VARCHAR(64) NULL,
  `diagnosed` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_public_farming_slot` (`plot_id`, `slot_index`),
  CONSTRAINT `fk_public_farming_slots_plot`
    FOREIGN KEY (`plot_id`) REFERENCES `public_farming_plots` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
