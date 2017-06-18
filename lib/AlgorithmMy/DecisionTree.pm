package Algorithm::DecisionTree;

#---------------------------------------------------------------------------
# Copyright (c) 2011 Avinash Kak. All rights reserved.
# This program is free software.  You may modify and/or
# distribute it under the same terms as Perl itself.
# This copyright notice must remain attached to the file.
#
# Algorithm::DecisionTree is a pure Perl implementation for
# constructing a decision tree from training examples of
# multidimensional data and then using the tree to classify
# such data subsequently.
# ---------------------------------------------------------------------------

use 5.6.1;
use strict;
use warnings;
use Carp;
use DBI;
use DBD::InterBase;

our $precision = 0.0001;
# Переменная для вывода информации о вероятности ошибки на тестовой выборке.
our $prob_error = 0;

#############################   Constructors  #######################

# Constructor for decision tree induction and classification with the tree:
sub new { 
    my ($class, %args) = @_;
    my @params = keys %args;
    croak "\nYou have used a wrong name for a keyword argument " .
          "--- perhaps a misspelling\n" 
          if check_for_illegal_params(@params) == 0;
    bless {
        _training_datafile           =>   $args{training_datafile} 
                                        || croak("training_datafile required"),
        _root_node                   =>    undef,
		_debug                       =>    $args{debug} || 0,
        _training_data_hash          =>    {},
        _samples_class_label_hash    =>    {},
        _class_names                 =>    [],
        _class_priors                =>    [],
		_test_data_hash          	 =>    {},
		_test_samples_class_label_hash =>  {},
    }, $class;
}


#################    Classify with Decision Tree  ###################

# use
sub classify {
    my $self = shift;
    my $root_node = shift;
	my @test_sample = @_;
	
    my $classification = $self->recursive_descent_for_classification($root_node, \@test_sample);
    return $classification;
}

# use
sub recursive_descent_for_classification {
    my $self = shift;
    my $node = shift;
	my $test_sample = shift;
    my @class_names = @{$self->{_class_names}};
    
	my @child = @{$node->get_children()};

	if (@child) {
		my $number_feature;
		$number_feature = $node->get_feature_number();

		my $value;
		$value = $node->get_value();

		if (${$test_sample}[$number_feature] < $value) {
			$self->recursive_descent_for_classification($child[0], $test_sample); 
		} else {
			$self->recursive_descent_for_classification($child[1], $test_sample);
		}
	} else {
		return $node->get_class_name();
	}
}    

#################    Decision Tree Construction  ###################

# use
sub construct_decision_tree_classifier {
    my $self = shift;
    my @class_names = @{$self->{_class_names}};
	my %samples_class_label_hash = %{$self->{_samples_class_label_hash}};
	my @key_node = keys %samples_class_label_hash;
	
	#for debug.
	my $training_data_hash = $self->{_training_data_hash};
	
    my @count_samples_on_classes;
	my $entropy = 0.0;
	$self->calculation_parameter_root_node(\$entropy, \@count_samples_on_classes);
	
	if ($self->{_debug}) {
		print "entropy $entropy \n";
		print "count_samples_on_classes @count_samples_on_classes \n";
	}
    my $root_node = Node->new(
		$entropy, 
        \@count_samples_on_classes
	);
    $self->{_root_node} = $root_node;
    $self->recursive_descent($root_node, \@key_node);
	
	if ($self->{_debug}) {
		print "count_wrong_samples " . $root_node->get_count_wrong_samples() . "\n";
		$root_node->print_node_created();
	
		#Проверка качества работы на обучающей выборке.
		my $count_error_training_data_hash;
		$count_error_training_data_hash = 0;
		
		foreach my $key (@key_node) {		 
			my @test_sample = @{$training_data_hash->{$key}};
			my $classification = recursive_descent_for_classification($self, $root_node, \@test_sample);
			if ($classification != $samples_class_label_hash{$key}) {
				$count_error_training_data_hash++;
			}
		}
		print "count error training_data_hash $count_error_training_data_hash\n";
		
		# Проверка качества работы на тестовой выборке.
		my %test_samples_class_label_hash = %{$self->{_test_samples_class_label_hash}};
		my @key_node_test = keys %test_samples_class_label_hash;

		my $test_data_hash = $self->{_test_data_hash};
		my $count_error_test;
		$count_error_test = 0;
		my @count_samples_on_classes_test_hash = map {0} @class_names;
		my @count_samples_error_test_hash = map {0} @class_names;
		foreach my $key (@key_node_test) {		 
			my @test_sample = @{$test_data_hash->{$key}};
			my $classification = recursive_descent_for_classification($self, $root_node, \@test_sample);
			$count_samples_on_classes_test_hash[$test_samples_class_label_hash{$key}]++;
			if ($classification != $test_samples_class_label_hash{$key}) {
				$count_samples_error_test_hash[$test_samples_class_label_hash{$key}]++;
				$count_error_test++;
			}
		}
		my $probability = $count_error_test / (@key_node_test);
		$prob_error += $probability;
		print "count error test $count_error_test  - $probability\n";
		print "count_samples_on_classes_test_hash @count_samples_on_classes_test_hash\n";
		print "count_samples_error_test_hash      @count_samples_error_test_hash\n";
		
		print "probability on classes ";
		foreach my $i (0..(@count_samples_on_classes_test_hash - 1)) {
			if ($count_samples_on_classes_test_hash[$i] != 0) {
				my $prob = 1 - $count_samples_error_test_hash[$i] / $count_samples_on_classes_test_hash[$i];
				printf "%.3f ", $prob;
			}
		}
		print "\n";
	}
    return $root_node;
}

# use
sub recursive_descent {
    my $self = shift;
    my $node = shift;
	# Массив ключей данного узла.
	my @key_node = @{$_[0]};	

	my $training_data_hash = $self->{_training_data_hash};
	my $samples_class_label_hash = $self->{_samples_class_label_hash};
	my $count_samples_on_classes = $node->get_count_samples_on_classes();
	my @class_names = @{$self->{_class_names}};
	my $entropy_root = $node->get_entropy();

	my $count_feature = @{$training_data_hash->{$key_node[0]}};
	
	my $max_entropy = $entropy_root;
	my $index_max_entropy = -1;
	my @count_samples_on_classes_left_max_entropy;
	my @count_samples_on_classes_right_max_entropy;
	my $entropy_left_max_entropy;
	my $entropy_right_max_entropy;
	my @key_node_max_entropy;
	my $feature_number_max_entropy;
	
	# Цикл по фичам.
	foreach my $feature_number (0..($count_feature - 1)) {

		# Отсортировать key_node по р/м признаку.
		# Сначала скачиваем в отдельный массив значения сортируемых фич.

		# Массив значений данной фичи.
		my @massive_values_feature;
		foreach my $key (@key_node) {
			push @massive_values_feature, $training_data_hash->{$key}[$feature_number];
		}
		

		my @massive_index;
		@massive_index = sort {$massive_values_feature[$a] <=> $massive_values_feature[$b]} 0..(@massive_values_feature - 1);

		my @copy_key_node;
		@copy_key_node = @key_node;

		foreach my $i (0..(@massive_index - 1)) {
			$key_node[$i] = $copy_key_node[$massive_index[$i]];	
		}

		@massive_values_feature = ();
		foreach my $key (@key_node) {
			push @massive_values_feature, $training_data_hash->{$key}[$feature_number];
		}
		
		# Рассчитать для каждого значения энтропию. Выбрать максимальную.
		my @count_samples_on_classes_left = @{$count_samples_on_classes};
		# Обнуляем массив.
		@count_samples_on_classes_left = map {0} @count_samples_on_classes_left;
		my @count_samples_on_classes_right = @{$count_samples_on_classes};

		my $count_elements_left;
		my $count_elements_right;
		$count_elements_left = 0;
		$count_elements_right = @key_node;
		
		# Рассматриваем (n - 1) вариантов разделения.
		foreach my $i (0..(@key_node - 2)) {
			my $name_class;
			$name_class = $samples_class_label_hash->{$key_node[$i]};
			my $index;
			foreach my $j (0..(@class_names - 1)) {
				if ($name_class eq $class_names[$j]) {
					$index = $j;
					last;
				}
			}
			if (!defined $index) {
				print "error 0\n";
			}
			$count_elements_left++;
			$count_elements_right--;
			$count_samples_on_classes_left[$index]++;
			$count_samples_on_classes_right[$index]--;
			
			if ((($massive_values_feature[$i + 1] - $massive_values_feature[$i]) < $precision)) {
				next;
			}
			
			my $entropy_left;
			my $entropy_right;
			$entropy_left = 0.0;
			$entropy_right = 0.0;
			foreach my $j (0..(@class_names - 1)) {
				$entropy_left += ($count_samples_on_classes_left[$j] ** 2);
				$entropy_right += ($count_samples_on_classes_right[$j] ** 2);
			}
			$entropy_left /= $count_elements_left;
			$entropy_right /= $count_elements_right;

			my $entropy;
			$entropy = $entropy_left + $entropy_right;
			
			if ($max_entropy < $entropy) {
				$max_entropy = $entropy;
				$index_max_entropy = $i;
				@count_samples_on_classes_left_max_entropy = @count_samples_on_classes_left;
				@count_samples_on_classes_right_max_entropy = @count_samples_on_classes_right;
				$entropy_left_max_entropy = $entropy_left;
				$entropy_right_max_entropy = $entropy_right;
				@key_node_max_entropy = @key_node;
				$feature_number_max_entropy = $feature_number;
			}
		}
	}
	
	# Не найдено лучшее разбиение останавливаем обучение.
	if ($index_max_entropy == -1) {
		my $index_max_count_class;
		$index_max_count_class = 0;
		foreach my $i (1..(@class_names - 1)) {
			if ($count_samples_on_classes->[$index_max_count_class] <
				$count_samples_on_classes->[$i]) {
				$index_max_count_class = $i;
			}
		}
		
		# Количество неверно опредленных примеров в данном узле.
		my $count_wrong_samples;
		$count_wrong_samples = @key_node - $count_samples_on_classes->[$index_max_count_class];
		$node->set_count_wrong_samples($count_wrong_samples);

		my $name_class_leaf;
		$name_class_leaf = $class_names[$index_max_count_class];
		$node->set_class_name($name_class_leaf);
		return;
	} else {

		# Расчет порогового значения. 
		# Такой сложный расчет связан с тем, что возможен случай, когда примеры имеют абсолютно одинаковые значения.
		my $value_node = $training_data_hash->{$key_node_max_entropy[$index_max_entropy]}[$feature_number_max_entropy];
		foreach my $i (($index_max_entropy + 1)..(@key_node_max_entropy - 1)) {
			my $next_value = $training_data_hash->{$key_node_max_entropy[$i]}[$feature_number_max_entropy];
			if (($next_value - $value_node) > $precision || ($i == (@key_node_max_entropy - 1))) {
				$value_node += $next_value;
				last;
			}
		}
		$value_node /= 2.0;

		# Устанавливаем пороговое значение для данного узла.
		$node->set_value($value_node);
		$node->set_feature_number($feature_number_max_entropy);

		my $child_node_left = Node->new(
			$entropy_left_max_entropy,
			\@count_samples_on_classes_left_max_entropy,
		);
		$node->add_child_link($child_node_left);
		
		# Рассчитываем количество примеров в левом узле.
		my $count_samples_left_node;
		$count_samples_left_node = 0.0;
		foreach my $i (@count_samples_on_classes_left_max_entropy) {
			$count_samples_left_node += $i;
		}
		my @key_node_left = @key_node_max_entropy[0..$index_max_entropy];
		
		my $min_count_samples_for_node = 15;

		# Определяем левый узел будет узлом или листом.
		if ($count_samples_left_node > $min_count_samples_for_node && $entropy_left_max_entropy > 0) {
			$self->recursive_descent($child_node_left, \@key_node_left);
		} else {
			# Определяем класс данного листа.
			my $index_max_count_class;
			$index_max_count_class = 0;
			foreach my $i (1..(@class_names - 1)) {
				if ($count_samples_on_classes_left_max_entropy[$index_max_count_class] <
					$count_samples_on_classes_left_max_entropy[$i]) {
					$index_max_count_class = $i;
				}
			}

			# Количество неверно опредленных примеров в данном узле.
			my $count_wrong_samples;
			$count_wrong_samples = @key_node_left - $count_samples_on_classes_left_max_entropy[$index_max_count_class];
			$child_node_left->set_count_wrong_samples($count_wrong_samples);
			
			my $name_class_leaf;
			$name_class_leaf = $class_names[$index_max_count_class];
			$child_node_left->set_class_name($name_class_leaf);
		}

		my $child_node_right = Node->new(
			$entropy_right_max_entropy,
			\@count_samples_on_classes_right_max_entropy,
		);
		$node->add_child_link($child_node_right);
		
		# Рассчитываем количество примеров в правом узле.
		my $count_samples_right_node;
		$count_samples_right_node = 0.0;
		foreach my $i (@count_samples_on_classes_right_max_entropy) {
			$count_samples_right_node += $i;
		}
		my @key_node_right = @key_node_max_entropy[($index_max_entropy + 1)..(@key_node - 1)];

		# Определяем правый узел будет узлом или листом.
		if ($count_samples_right_node > $min_count_samples_for_node && $entropy_left_max_entropy > 0) {
			$self->recursive_descent($child_node_right, \@key_node_right);
		} else {
			# Определяем и устанавливаем класс данного листа.
			my $index_max_count_class;
			$index_max_count_class = 0;
			foreach my $i (1..(@class_names - 1)) {
				if ($count_samples_on_classes_right_max_entropy[$index_max_count_class] <
						$count_samples_on_classes_right_max_entropy[$i]) {
					$index_max_count_class = $i;
				}
			}
			
			# Количество неверно опредленных примеров в данном узле.
			my $count_wrong_samples;
			$count_wrong_samples = @key_node_right - $count_samples_on_classes_right_max_entropy[$index_max_count_class];
			$child_node_right->set_count_wrong_samples($count_wrong_samples);
			
			my $name_class_leaf;
			$name_class_leaf = $class_names[$index_max_count_class];
			$child_node_right->set_class_name($name_class_leaf);
		}
		
		my $count_wrong_samples;
		$count_wrong_samples = $child_node_left->get_count_wrong_samples() + 
							   $child_node_right->get_count_wrong_samples();
		$node->set_count_wrong_samples($count_wrong_samples);
	}
}

sub number_of_nodes_created {
    Node->how_many_nodes();
}


#################    Entropy Calculators       #####################

# use
# Расчет энтропии и количества примеров всех классов.
sub calculation_parameter_root_node {
	my $self = shift;
    my $ref_on_entropy = shift;
	my $ref_on_count_samples_on_classes = shift;
	my @class_names = @{$self->{_class_names}};
    my %samples_class_label_hash = %{$self->{_samples_class_label_hash}};

	my $total_num_of_samples = keys %samples_class_label_hash;
    my $entropy = 0.0;
    foreach my $class (@class_names) {
        my $count = $self->prior_probability_for_class($class);
		push @{$ref_on_count_samples_on_classes}, $count;
        $entropy += $count * $count;
    }
	$entropy /= $total_num_of_samples;
	${$ref_on_entropy} = $entropy;
}

# use
sub prior_probability_for_class {
    my $self = shift;
    my $class = shift;
    my %samples_class_label_hash = %{$self->{_samples_class_label_hash}};
    my $total_num_of_samples = keys %samples_class_label_hash;
    my @values = values %samples_class_label_hash;
    my @trues = grep {$_ eq $class} @values;
    return (1.0 * @trues); 
}

###################  Read Training Data From File  ###################

# use
sub get_training_data {
    my $self = shift;
    my %samples_class_label_hash;
    my %training_data_hash;
    my $training_data_file = $self->{_training_datafile};
    my $recording_training_data = 0;
    my %column_label_hash;
    open INPUT, $training_data_file
                || "unable to open training data file: $!";
	
	my %test_data_hash;
	my %test_samples_class_label_hash;
	
	my %temp_data_hash;
	my %temp_samples_class_label_hash;

	my $count_samples;
	$count_samples = 0;
    while (<INPUT>) {
        chomp;
        next if /^[\s=#]*$/;
        if ( (/^class/i) && !$recording_training_data) {
            $_ =~ /^\s*class names:\s*([ \S]+)\s*/i;
            my @class_names = split /\s+/, $1;
            $self->{_class_names} = \@class_names;
            next;
        } elsif (/^training data/i) {
            $recording_training_data = 1;
            next;
        } elsif ($recording_training_data) {
			my @record = split /\s+/;

			my $class = $record[1];
			if ($count_samples % 10 != 0) {				
				$samples_class_label_hash{$record[0]} = $class;
				$training_data_hash{$record[0]} = [];
				foreach my $i (2..@record-1) {
					push @{$training_data_hash{$record[0]}}, $record[$i];
				}
			} else {
				$test_samples_class_label_hash{$record[0]} = $class;
				$test_data_hash{$record[0]} = [];
				foreach my $i (2..@record-1) {
					push @{$test_data_hash{$record[0]}}, $record[$i];
				}
			}
			$count_samples++;
        }
    }
	
	die ("Function get_training_data: count_samples == 0.\n") if ($count_samples == 0);
	
	if ($self->{_debug}) {
		print "count_samples $count_samples\n";
	}
	
    $self->{_samples_class_label_hash} = \%samples_class_label_hash;
    $self->{_training_data_hash} = \%training_data_hash;
	$self->{_test_samples_class_label_hash} = \%test_samples_class_label_hash;
    $self->{_test_data_hash} = \%test_data_hash;
}    

sub get_training_data_from_hash {
    my $self = shift;
	my $training_data_hash = shift;
	
	die ("Function get_training_data_from_hash: Error load from hash\n") if (!defined $training_data_hash);

	my @class_names = ('1', '2', '3');

    my %samples_class_label_hash;
    my %training_data_hash;
    
	my %test_data_hash;
	my %test_samples_class_label_hash;
	my $count_samples;
	$count_samples = 0;
   
	while (my ($key, $value) = each(%$training_data_hash)) {
		my @record = @$value;

		my $class = $record[1];
		if ($count_samples % 10 != 0) {			
			$samples_class_label_hash{$record[0]} = $class;
			$training_data_hash{$record[0]} = [];
			foreach my $i (2..@record-1) {
				push @{$training_data_hash{$record[0]}}, $record[$i];
			}
		} else {
			$test_samples_class_label_hash{$record[0]} = $class;
			$test_data_hash{$record[0]} = [];
			foreach my $i (2..@record-1) {
				push @{$test_data_hash{$record[0]}}, $record[$i];
			}
		}
		$count_samples++;
    }
	
	die ("Function get_training_data_from_hash: count_samples == 0.\n") if ($count_samples == 0);
	
	if ($self->{_debug}) {
		print "count_samples $count_samples\n";
	}

    $self->{_samples_class_label_hash} = \%samples_class_label_hash;
    $self->{_training_data_hash} = \%training_data_hash;
	$self->{_test_samples_class_label_hash} = \%test_samples_class_label_hash;
    $self->{_test_data_hash} = \%test_data_hash;
	$self->{_class_names} = \@class_names;
}    

sub show_training_data {
    my $self = shift;
    my @class_names = @{$self->{_class_names}};
    my %features_and_values_hash = %{$self->{_features_and_values_hash}};
    my %samples_class_label_hash = %{$self->{_samples_class_label_hash}};
    my %training_data_hash = %{$self->{_training_data_hash}};
    print "\n\nClass Names: @class_names\n";
    print "\n\nFeatures and Their Possible Values:\n\n";
    while ( my ($k, $v) = each %features_and_values_hash ) {
        print "$k --->  @{$features_and_values_hash{$k}}\n";
    }
    print "\n\nSamples vs. Class Labels:\n\n";
    foreach my $kee (sort {sample_index($a) <=> sample_index($b)} 
                                      keys %samples_class_label_hash) {
        print "$kee =>  $samples_class_label_hash{$kee}\n";
    }
    print "\n\nTraining Samples:\n\n";
    foreach my $kee (sort {sample_index($a) <=> sample_index($b)} 
                                      keys %training_data_hash) {
        print "$kee =>  @{$training_data_hash{$kee}}\n";
    }
}

sub get_class_names {
    my $self = shift;
    return @{$self->{_class_names}}
}

###########################  Utility Routines  #####################

sub sample_index {
    my $arg = shift;
    $arg =~ /_(.+)$/;
    return $1;
}    

sub check_for_illegal_params {
    my @params = @_;
    my @legal_params = qw / training_datafile
                            debug
                          /;
    my $found_match_flag;
    foreach my $param (@params) {
        foreach my $legal (@legal_params) {
            $found_match_flag = 0;
            if ($param eq $legal) {
                $found_match_flag = 1;
                last;
            }
        }
        last if $found_match_flag == 0;
    }
    return $found_match_flag;
}

# Сохранение дерева в хэш для передачи в БД.
sub store_tree_in_hash {
	my $self = shift;
	my $root_node = shift;
	my %hash_tree;

	traversal_tree_for_store($root_node, \%hash_tree);

	return \%hash_tree;
}

sub traversal_tree_for_store {
	my $node = shift;
	my $hash = shift;

	my $serial_num = $node->get_serial_num();
	push @{$hash->{$serial_num}}, $serial_num;
	my $parameter = \@{$hash->{$serial_num}};
	
	my @child = @{$node->get_children()};
	
	# Если узел имеет детей, значит - это внутренний узел.
	if (@child) {
		push @{$parameter}, "internal_node";
		push @{$parameter}, $node->get_feature_number();
		push @{$parameter}, $node->get_value();
		push @{$parameter}, $child[0]->get_serial_num();
		push @{$parameter}, $child[1]->get_serial_num();
		traversal_tree_for_store($child[0], $hash);
		traversal_tree_for_store($child[1], $hash);
	} else {
		push @{$parameter}, $node->get_class_name();
		push @{$parameter}, "-1";
		push @{$parameter}, "-1";
		push @{$parameter}, "-1";
		push @{$parameter}, "-1";
	}
}

# Создание дерева из хэша.
sub load_tree_from_hash {
	my $self = shift;
	my $hash_tree = shift;
	
	# Проверяем размер хэша.
	my $size_of_hash = scalar keys %{$hash_tree};
	die ("Function load_tree_from_hash: Size of hash = 0.\n") if ($size_of_hash == 0);
	
	my $root_node = Node->new();
	
	my @parameter = @{$hash_tree->{0}};
	
	# Проверяем количество элементов в массиве по данному узлу, их должно быть строго 6.
	die ("Function load_tree_from_hash: Count paramater for node not equal 6.\n") if ((scalar @parameter) != 6);
	
	if ($parameter[1] eq "internal_node") {
		$root_node->set_feature_number($parameter[2]);
		$root_node->set_value($parameter[3]);
		my $left_child = traversal_tree_for_load($parameter[4], $hash_tree);
		my $right_child = traversal_tree_for_load($parameter[5], $hash_tree);

		$root_node->add_child_link($left_child);
		$root_node->add_child_link($right_child);
	} else {
		$root_node->set_class_name($parameter[1]);
	}

	return $root_node;
}

sub traversal_tree_for_load {
	my $serial_number_node = shift;
	my $hash_tree = shift;

	my $node = Node->new();
	
	my @parameter = @{$hash_tree->{$serial_number_node}};
	
	# Проверяем количество элементов в массиве по данному узлу, их должно быть строго 6.
	die ("Function traversal_tree_for_load: Count paramater for node not equal 6.\n") if ((scalar @parameter) != 6);
	
	if ($parameter[1] eq "internal_node") {
		$node->set_feature_number($parameter[2]);
		$node->set_value($parameter[3]);
		my $left_child = traversal_tree_for_load($parameter[4], $hash_tree);
		my $right_child = traversal_tree_for_load($parameter[5], $hash_tree);

		$node->add_child_link($left_child);
		$node->add_child_link($right_child);
	} else {
		$node->set_class_name($parameter[1]);
	}
	
	return $node;
}

sub get_prob_error() {
	return $prob_error;
}

######################  Class Node  ###########################

# The nodes of the decision tree are instances of this class:

package Node;

use strict;                                                         
use Carp;

our $nodes_created = 0;

sub new {
	my ($class, $entropy, $count_samples_on_classes, $feature_number, $value, $class_name) = @_; 
    bless {                                                         
        _serial_number => $nodes_created++,
        _entropy => $entropy,
		_count_samples_on_classes => $count_samples_on_classes,
		_feature_number => $feature_number,                                       
		_value => $value,
		_class_name => $class_name,
		_count_wrong_samples => 0,
        _linked_to => [],                                          
    }, $class;                                                     
}

sub print_node_created {
	print "node created $nodes_created \n";
}

sub get_serial_num {
    my $self = shift;
    $self->{_serial_number};
}

sub get_feature_number {                                  
    my $self = shift;                              
    return $self->{_feature_number};                    
}

sub set_feature_number {
    my $self = shift;
    my $feature_number = shift;
    $self->{_feature_number} = $feature_number;
}

sub get_count_wrong_samples {                                  
    my $self = shift;                              
    return $self->{_count_wrong_samples};                    
}

sub set_count_wrong_samples {
    my $self = shift;
    my $count_wrong_samples = shift;
    $self->{_count_wrong_samples} = $count_wrong_samples;
}

sub get_entropy {                                  
    my $self = shift;                              
    return $self->{ _entropy };                    
}

sub get_count_samples_on_classes {                                  
    my $self = shift;                              
    return $self->{_count_samples_on_classes};                    
}

sub get_value {                                  
    my $self = shift;                              
    return $self->{_value_node};                    
}

sub set_value {                                  
    my $self = shift;
	my $value_node = shift;
    $self->{_value_node} = $value_node;                    
}

sub set_class_name {                                  
    my $self = shift;
	my $class_name = shift;
    $self->{_class_name} = $class_name;                    
}

sub get_class_name {
    my $self = shift;
    return $self->{_class_name};
}

sub get_children {       
    my $self = shift;                   
    return $self->{_linked_to};
}

sub add_child_link {         
    my ($self, $new_node, ) = @_;                            
    push @{$self->{_linked_to}}, $new_node;                  
}

sub delete_all_links {                  
    my $self = shift;                   
    $self->{_linked_to} = undef;        
}

sub display_node {
    my $self = shift; 
    my $feature_at_node = $self->get_feature() || " ";
    my $entropy_at_node = $self->get_entropy();
    my @class_probabilities = @{$self->get_class_probabilities()};
    my $serial_num = $self->get_serial_num();
    my @branch_features_and_values = @{$self->get_branch_features_and_values()};
    print "\n\nNODE $serial_num:\n   Branch features and values to this node: @branch_features_and_values\n   Class probabilities at current node: @class_probabilities\n   Entropy at current node: $entropy_at_node\n   Best feature test at current node: $feature_at_node\n\n";
}

sub display_decision_tree {
	my $self = shift;
    my $offset = shift;
    my $serial_num = $self->get_serial_num();
    if (@{$self->get_children()}) {
        my $feature_at_node = $self->get_feature_number();
		my $value = $self->get_value();
        my $entropy_at_node = $self->get_entropy();        
		
		my @count_samples_on_classes;
		if (defined $self->get_count_samples_on_classes) {
			@count_samples_on_classes = @{$self->get_count_samples_on_classes};
		}
		
		print "NODE $serial_num:  $offset feature_number: $feature_at_node value: $value";
		if (defined $entropy_at_node) {
			print " entropy: $entropy_at_node class probs: @count_samples_on_classes ";
		}
		print "\n";
		
        $offset = $offset . "   ";
        foreach my $child (@{$self->get_children()}) {
            $child->display_decision_tree($offset);
        }
    } else {
        my $entropy_at_node = $self->get_entropy();
		my $class_name = $self->get_class_name();
		
		my @count_samples_on_classes;
		if (defined $self->get_count_samples_on_classes) {
			@count_samples_on_classes = @{$self->get_count_samples_on_classes};
		}
		
		print "NODE $serial_num:  $offset ";
		if (defined $entropy_at_node) {
			print " entropy: $entropy_at_node class probs: @count_samples_on_classes ";
		}
		print "  class_name: $class_name\n"
    }
}
1;

