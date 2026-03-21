terraform {
  required_version = ">= 1.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0"
    }
  }
}

provider "oci" {
  region = var.region
}

# ─── Data Sources ────────────────────────────────────────────────────────────

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

locals {
  is_arm = var.shape == "VM.Standard.A1.Flex"
}

# Latest Ubuntu 24.04 for the chosen shape
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ─── Network (all free tier) ────────────────────────────────────────────────

resource "oci_core_vcn" "vpn" {
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "family-vpn-vcn"
  dns_label      = "vpnvcn"
}

resource "oci_core_internet_gateway" "vpn" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vpn.id
  display_name   = "family-vpn-igw"
  enabled        = true
}

resource "oci_core_route_table" "vpn" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vpn.id
  display_name   = "family-vpn-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.vpn.id
  }
}

resource "oci_core_security_list" "vpn" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vpn.id
  display_name   = "family-vpn-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # SSH — optional, restrict via admin_ssh_cidr
  ingress_security_rules {
    protocol = "6"
    source   = var.admin_ssh_cidr
    tcp_options {
      min = 22
      max = 22
    }
  }

  # VLESS+Reality (looks like HTTPS to DPI)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # AmneziaWG
  ingress_security_rules {
    protocol = "17"
    source   = "0.0.0.0/0"
    udp_options {
      min = 8443
      max = 8443
    }
  }
}

resource "oci_core_subnet" "vpn" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.vpn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "family-vpn-subnet"
  dns_label         = "vpnsub"
  route_table_id    = oci_core_route_table.vpn.id
  security_list_ids = [oci_core_security_list.vpn.id]
}

# ─── Compute Instance (free tier) ───────────────────────────────────────────

resource "oci_core_instance" "vpn" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = "family-vpn"
  shape               = var.shape

  dynamic "shape_config" {
    for_each = local.is_arm ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_gb
    }
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.vpn.id
    assign_public_ip = true
    display_name     = "family-vpn-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init-docker.yaml.tpl", {
      dockerfile_b64 = base64encode(file("${path.module}/../docker/Dockerfile"))
      entrypoint_b64 = base64encode(file("${path.module}/../docker/entrypoint.sh"))
      compose_b64    = base64encode(file("${path.module}/../docker-compose.yml"))
    }))
  }
}
